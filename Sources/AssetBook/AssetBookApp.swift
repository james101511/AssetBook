import SwiftUI
import UniformTypeIdentifiers

@main
struct AssetBookApp: App {
    @State private var store = PortfolioStore.shared

    #if os(macOS)
    init() {
        // 用 `swift run` 啟動時讓視窗出現在前景；在 Xcode 專案中沒有影響。
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.portfolio, store)
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 780)
        .commands {
            CommandGroup(after: .newItem) {
                Button("更新資產…") { store.isUpdating = true }
                    .keyboardShortcut("u", modifiers: .command)
                Button("新增帳戶…") { store.isAddingAccount = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .importExport) {
                Button("匯出備份…") { store.isExporting = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("匯入備份…") { store.isImporting = true }
                Divider()
                Button("在 Finder 中顯示資料檔") { store.revealDataFile() }
            }
            CommandGroup(after: .toolbar) {
                Toggle("隱藏金額", isOn: $store.hideAmounts)
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(\.portfolio, store)
                .frame(width: 420)
        }
        #endif
    }
}

enum AppTab: Hashable {
    case overview, accounts(AccountsFilter), history
}

/// 帳戶頁的分頁：全部（摘要）或單一分類
enum AccountsFilter: String, CaseIterable, Identifiable, Hashable {
    case all, crypto, stocks, cash, liability

    var id: Self { self }

    init(_ category: AssetCategory) { self = AccountsFilter(rawValue: category.rawValue) ?? .all }

    var category: AssetCategory? { AssetCategory(rawValue: rawValue) }

    var shortTitle: String {
        switch self {
        case .all: "全部"
        case .crypto: "加密"
        case .stocks: "股票"
        case .cash: "現金"
        case .liability: "負債"
        }
    }

    var title: String { category?.title ?? "全部帳戶" }
    var symbol: String { category?.symbol ?? "square.grid.2x2.fill" }
}

struct RootView: View {
    @Environment(\.portfolio) private var store
    @State private var tab: AppTab = .overview
    @State private var pendingImport: Data?
    /// iPhone／iPad：帳戶頁目前的分頁（記住上次停留的位置）
    @AppStorage("accountsFilter") private var accountsFilter: AccountsFilter = .all

    var body: some View {
        @Bindable var store = store
        navigation
        .background { categoryShortcuts }
        .sheet(isPresented: $store.isUpdating) {
            UpdateSheet(base: store.latest, accounts: store.activeAccounts)
                .environment(\.portfolio, store)
        }
        .sheet(isPresented: $store.isAddingAccount) {
            AccountEditor()
                .environment(\.portfolio, store)
        }
        .fileExporter(isPresented: $store.isExporting,
                      document: store.isExporting ? (try? store.exportData()).map(BackupDocument.init) : nil,
                      contentType: .json,
                      defaultFilename: "AssetBook-\(Fmt.day(.now))") { result in
            if case .failure(let error) = result { store.alertMessage = "匯出失敗：\(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $store.isImporting, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                pendingImport = try Data(contentsOf: url)
            } catch {
                store.alertMessage = "無法讀取檔案：\(error.localizedDescription)"
            }
        }
        .confirmationDialog("以匯入的檔案取代目前所有資料？",
                            isPresented: .init(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                            titleVisibility: .visible) {
            Button("取代", role: .destructive) {
                guard let data = pendingImport else { return }
                do { try store.importData(data) } catch {
                    store.alertMessage = "這個檔案不是有效的 AssetBook 備份：\(error.localizedDescription)"
                }
                pendingImport = nil
            }
        } message: {
            Text("目前的資料會先自動備份到 backups 資料夾。")
        }
        .alert("AssetBook", isPresented: .init(get: { store.alertMessage != nil }, set: { if !$0 { store.alertMessage = nil } })) {
            Button("好") { store.alertMessage = nil }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    #if os(macOS)
    /// Mac：原生雙欄側邊欄，右側依選取整個換成對應的頁面。
    /// 不用 TabView 的 sidebarAdaptable：它在分頁之間共用底層列表，
    /// 各分頁的列表結構不同時，切換幾次就會卡住。
    private var navigation: some View {
        NavigationSplitView {
            List(selection: Binding(get: { tab }, set: { if let t = $0 { tab = t } })) {
                Label("總覽", systemImage: "chart.pie.fill").tag(AppTab.overview)
                Label("歷史紀錄", systemImage: "clock.arrow.circlepath").tag(AppTab.history)
                Section("帳戶") {
                    ForEach(AccountsFilter.allCases) { f in
                        Label(f.title, systemImage: f.symbol).tag(AppTab.accounts(f))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            NavigationStack { detail(for: tab) }
                .id(tab)
                .environment(\.portfolio, store)
        }
    }

    @ViewBuilder private func detail(for tab: AppTab) -> some View {
        switch tab {
        case .overview: DashboardView(tab: $tab)
        case .accounts(let f): AccountsView(filter: sidebarFilter(f), showsPicker: false)
        case .history: HistoryView()
        }
    }
    #else
    /// iPhone：底部分頁；iPad：可收合的側邊欄
    private var navigation: some View {
        TabView(selection: $tab) {
            Tab("總覽", systemImage: "chart.pie.fill", value: .overview) {
                NavigationStack { DashboardView(tab: $tab) }
                    .environment(\.portfolio, store)
            }
            Tab("帳戶", systemImage: "building.columns.fill", value: .accounts(.all)) {
                NavigationStack { AccountsView(filter: $accountsFilter) }
                    .environment(\.portfolio, store)
            }
            Tab("歷史紀錄", systemImage: "clock.arrow.circlepath", value: .history) {
                NavigationStack { HistoryView() }
                    .environment(\.portfolio, store)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
    #endif

    /// Mac 側邊欄：每個分頁固定顯示自己的分類（不能跟著目前選取變動，否則切換時
    /// 正要離開的分頁也會重畫，側邊欄會發生重入而卡住）；「全部」裡點分類卡片才切換側邊欄。
    private func sidebarFilter(_ f: AccountsFilter) -> Binding<AccountsFilter> {
        Binding(get: { f }, set: { tab = .accounts($0) })
    }

    /// ⌘1–⌘5：全部、加密貨幣、股票、現金、負債
    private var categoryShortcuts: some View {
        ForEach(Array(AccountsFilter.allCases.enumerated()), id: \.element) { i, f in
            Button(f.title) {
                withAnimation(.snappy) {
                    #if os(macOS)
                    tab = .accounts(f)
                    #else
                    accountsFilter = f
                    tab = .accounts(.all)
                    #endif
                }
            }
            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }
}

struct SettingsView: View {
    @Environment(\.portfolio) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("漲跌顏色", selection: $store.redMeansUp) {
                    Text("紅漲綠跌").tag(true)
                    Text("綠漲紅跌").tag(false)
                }
                Toggle("隱藏金額", isOn: $store.hideAmounts)
                Toggle("自動帶入最新匯率與幣價", isOn: $store.autoFetchQuotes)
            } footer: {
                Text("隱藏金額適合在公共場合或分享螢幕時使用。自動帶入會在開啟「更新資產」時從網路取得報價（ExchangeRate-API、CoinGecko），不會送出任何個人資料。")
            }

            Section {
                Button("匯出備份…") { store.isExporting = true }
                Button("匯入備份…") { store.isImporting = true }
                #if os(macOS)
                Button("在 Finder 中顯示資料檔") { store.revealDataFile() }
                #endif
                Button("重新下載所有帳戶圖示") { IconLoader.shared.clearDownloaded() }
            } header: {
                Text("資料")
            } footer: {
                Text("所有變更會自動存檔，並在 backups 資料夾保留最近 30 個版本。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("設定")
    }
}
