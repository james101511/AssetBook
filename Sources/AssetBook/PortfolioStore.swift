import SwiftUI
import Observation

extension EnvironmentValues {
    /// 預設值就是共用的 store：macOS 上部分容器（側邊欄分頁、工具列、sheet）
    /// 不會把 environment 往下傳，有預設值就不會因此崩潰，而且仍是同一份資料。
    var portfolio: PortfolioStore {
        get { self[PortfolioKey.self] }
        set { self[PortfolioKey.self] = newValue }
    }
}

private struct PortfolioKey: EnvironmentKey {
    static let defaultValue = PortfolioStore.shared
}

/// App 的狀態。所有修改都會自動存到 JSON 檔（見 Persistence）。
@Observable
final class PortfolioStore {
    private(set) var accounts: [Account]
    /// 依日期由舊到新排序
    private(set) var snapshots: [Snapshot]

    // 設定（會存檔）
    var hideAmounts = false { didSet { persist() } }
    /// 台灣慣例：紅漲綠跌
    var redMeansUp = true { didSet { persist() } }
    /// 開啟「更新資產」時自動帶入最新匯率與幣價
    var autoFetchQuotes = true { didSet { persist() } }
    /// 外觀：跟隨系統、淺色或深色
    var appearance: Appearance = .system { didSet { persist(); appearance.apply() } }

    // 介面狀態
    var isUpdating = false
    var isAddingAccount = false
    var isExporting = false
    /// 匯出成試算表（CSV）
    var isExportingSheet = false
    var isImporting = false
    /// 讀檔或存檔失敗時顯示給使用者的訊息
    var alertMessage: String?

    @ObservationIgnored private var persistence: Persistence?

    static let shared = PortfolioStore.load()

    init(accounts: [Account], snapshots: [Snapshot]) {
        self.accounts = accounts
        self.snapshots = snapshots.sorted { $0.date < $1.date }
    }

    // MARK: 存檔

    /// 讀取資料檔；第一次使用時以試算表的三期資料當作初始內容。
    static func load(from persistence: Persistence = .default) -> PortfolioStore {
        let store: PortfolioStore
        var message: String?
        do {
            if let data = try persistence.load() {
                store = PortfolioStore(accounts: data.accounts, snapshots: data.snapshots)
                store.redMeansUp = data.settings.redMeansUp
                store.hideAmounts = data.settings.hideAmounts
                store.autoFetchQuotes = data.settings.autoFetchQuotes
                store.appearance = data.settings.appearance
            } else {
                store = .sample
            }
        } catch {
            let moved = persistence.quarantine()
            store = .sample
            message = "資料檔無法讀取，已改用範例資料。原本的檔案保留在：\n\(moved?.path ?? persistence.fileURL.path)\n\n也可以從「匯入備份」還原 backups 資料夾中的備份。"
        }
        store.persistence = persistence
        store.persist()
        store.alertMessage = message
        return store
    }

    var dataFileURL: URL? { persistence?.fileURL }

    func copySheetToClipboard() {
        SheetExport.copyToClipboard(self)
        alertMessage = "已複製 \(snapshots.count) 筆紀錄的表格。到 Google 試算表點一格（例如 A1），按 ⌘V 貼上即可。"
    }

    func revealDataFile() {
        #if os(macOS)
        if let url = dataFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        #endif
    }

    private var storedData: StoredData {
        StoredData(accounts: accounts, snapshots: snapshots,
                   settings: .init(redMeansUp: redMeansUp, hideAmounts: hideAmounts,
                                  autoFetchQuotes: autoFetchQuotes, appearance: appearance))
    }

    private func persist() {
        guard let persistence else { return }
        do {
            try persistence.save(storedData)
        } catch {
            alertMessage = "存檔失敗：\(error.localizedDescription)"
        }
    }

    func exportData() throws -> Data {
        try Persistence.encoder.encode(storedData)
    }

    /// 以匯入的資料取代目前全部資料（取代前會先備份）。
    func importData(_ data: Data) throws {
        let imported = try Persistence.decoder.decode(StoredData.self, from: data)
        let saved = persistence
        persistence = nil   // 批次修改，最後只存一次
        accounts = imported.accounts
        snapshots = imported.snapshots.sorted { $0.date < $1.date }
        redMeansUp = imported.settings.redMeansUp
        hideAmounts = imported.settings.hideAmounts
        autoFetchQuotes = imported.settings.autoFetchQuotes
        appearance = imported.settings.appearance
        persistence = saved
        persist()
    }

    var latest: Snapshot? { snapshots.last }

    func snapshot(before s: Snapshot) -> Snapshot? {
        snapshots.last { $0.date < s.date }
    }

    /// 包含已封存的帳戶，用於計算歷史數字
    func accounts(in category: AssetCategory) -> [Account] {
        accounts.filter { $0.category == category }
    }

    /// 目前使用中的帳戶（更新畫面與帳戶列表）
    var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    func activeAccounts(in category: AssetCategory) -> [Account] {
        activeAccounts.filter { $0.category == category }
    }

    var archivedAccounts: [Account] { accounts.filter(\.isArchived) }

    func account(id: UUID) -> Account? { accounts.first { $0.id == id } }

    /// 有幾筆紀錄包含這個帳戶
    func recordCount(of account: Account) -> Int {
        snapshots.filter { $0.amounts[account.id] != nil }.count
    }

    var activeCategories: [AssetCategory] {
        AssetCategory.allCases.filter { !accounts(in: $0).isEmpty }
    }

    var daysSinceLastUpdate: Int? {
        guard let latest else { return nil }
        return Calendar.current.dateComponents([.day], from: latest.date, to: .now).day
    }

    // MARK: 估值

    func rate(_ currency: Currency, in s: Snapshot) -> Double {
        switch currency {
        case .twd: 1
        case .usd: s.quotes[.usdTWD] ?? 0
        case .jpy: s.quotes[.jpyTWD] ?? 0
        }
    }

    /// 帳戶幣別的價值（持有數量會乘上報價）。
    func nativeValue(of account: Account, in s: Snapshot) -> Double? {
        if case .portfolio = account.valuation {
            let positions = s.holdings[account.id] ?? []
            guard s.amounts[account.id] != nil || !positions.isEmpty else { return nil }
            return (s.amounts[account.id] ?? 0) + positionsValue(positions, in: s)
        }
        guard let amount = s.amounts[account.id] else { return nil }
        switch account.valuation {
        case .balance: return amount
        case .holding(let q): return amount * (s.quotes[q] ?? 0)
        case .portfolio: return nil
        }
    }

    /// 持股市值（以帳戶幣別計）
    func positionsValue(_ positions: [Position], in s: Snapshot) -> Double {
        positions.reduce(0) { $0 + $1.shares * (s.stockPrices[$1.symbol] ?? 0) }
    }

    /// 帳戶的價值會不會隨市場變動（股價、幣價或匯率）
    func isMarketLinked(_ account: Account) -> Bool {
        if account.currency != .twd { return true }
        switch account.valuation {
        case .balance: return false
        case .holding, .portfolio: return true
        }
    }

    /// 以台幣計，負債為負值。
    func value(of account: Account, in s: Snapshot) -> Double {
        let v = (nativeValue(of: account, in: s) ?? 0) * rate(account.currency, in: s)
        return account.category.isLiability ? -v : v
    }

    func total(_ category: AssetCategory, in s: Snapshot) -> Double {
        accounts(in: category).reduce(0) { $0 + value(of: $1, in: s) }
    }

    func total(_ currency: Currency, in s: Snapshot) -> Double {
        accounts.filter { $0.currency == currency && !$0.category.isLiability }
            .reduce(0) { $0 + value(of: $1, in: s) }
    }

    func netWorth(_ s: Snapshot) -> Double {
        accounts.reduce(0) { $0 + value(of: $1, in: s) }
    }

    func grossAssets(_ s: Snapshot) -> Double {
        accounts.filter { !$0.category.isLiability }.reduce(0) { $0 + value(of: $1, in: s) }
    }

    // MARK: 變更

    /// 同一天只保留一筆紀錄，再次儲存會覆蓋。
    func save(_ snapshot: Snapshot) {
        snapshots.removeAll { Calendar.current.isDate($0.date, inSameDayAs: snapshot.date) }
        snapshots.append(snapshot)
        snapshots.sort { $0.date < $1.date }
        persist()
    }

    func hasSnapshot(on date: Date) -> Bool {
        snapshots.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func delete(_ snapshot: Snapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        persist()
    }

    func add(_ account: Account) {
        accounts.append(account)
        persist()
    }

    // MARK: 即時估值

    enum LiveStatus: Equatable { case idle, loading, ready, failed }

    private(set) var liveQuotes: [Quote: Double] = [:]
    private(set) var liveStocks: [String: StockQuote] = [:]
    private(set) var liveUpdatedAt: Date?
    private(set) var liveStatus: LiveStatus = .idle
    private(set) var liveErrors: [String] = []

    static let liveSnapshotID = UUID(uuidString: "00000000-0000-0000-0000-00000000117E")!

    /// 最新紀錄的持股與餘額 × 現在的報價
    var liveSnapshot: Snapshot? {
        guard let latest, liveUpdatedAt != nil else { return nil }
        return Snapshot(id: Self.liveSnapshotID, date: liveUpdatedAt ?? .now,
                        quotes: latest.quotes.merging(liveQuotes) { _, new in new },
                        amounts: latest.amounts, holdings: latest.holdings,
                        stockPrices: latest.stockPrices.merging(liveStocks.mapValues(\.price)) { _, new in new })
    }

    /// 最新紀錄裡所有持股的代號
    var heldSymbols: [String] {
        guard let latest else { return [] }
        return Array(Set(latest.holdings.values.flatMap { $0.map(\.symbol) })).sorted()
    }

    var isLiveStale: Bool {
        guard let liveUpdatedAt else { return true }
        return Date.now.timeIntervalSince(liveUpdatedAt) > 300
    }

    /// 即時估值是根據哪一筆紀錄算的
    @ObservationIgnored private(set) var liveBaseID: UUID?

    /// 每次重新整理遞增；只採用最新一次請求的結果
    @ObservationIgnored private var liveRequestID = 0

    @MainActor
    func refreshLive() async {
        guard latest != nil else { return }
        liveRequestID += 1
        let requestID = liveRequestID
        liveStatus = .loading
        async let quotes = QuoteService.fetch(for: .now)
        async let stocks = StockService.quotes(heldSymbols)
        let (q, s) = await (quotes, stocks)
        // 已有更新的請求（例如剛存了新紀錄），這次的結果作廢
        guard requestID == liveRequestID else { return }
        // 被取消的請求不算失敗，保留原本的數字
        if Task.isCancelled {
            liveStatus = liveUpdatedAt == nil ? .idle : .ready
            return
        }
        liveQuotes = q.values
        liveStocks = s.quotes
        liveBaseID = latest?.id
        liveErrors = q.errors + s.errors
        let gotAnything = !q.values.isEmpty || !s.quotes.isEmpty
        if gotAnything { liveUpdatedAt = .now }
        liveStatus = gotAnything ? .ready : .failed
    }

    /// 把「輸入餘額」的股票帳戶改成持股明細。過去的金額會當作帳戶現金保留，歷史不變。
    func convertToPortfolio(_ account: Account) {
        var a = account
        a.valuation = .portfolio
        update(a)
    }

    func update(_ account: Account) {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[i] = account
        persist()
    }

    func setArchived(_ account: Account, _ archived: Bool) {
        var a = account
        a.isArchived = archived
        update(a)
    }

    /// 永久刪除帳戶，連同所有紀錄中的金額
    func delete(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        for i in snapshots.indices { snapshots[i].amounts[account.id] = nil }
        IconLoader.removeCustom(accountID: account.id)
        persist()
    }
}
