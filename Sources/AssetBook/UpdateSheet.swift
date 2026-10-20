import SwiftUI

/// 「更新資產」：取代每週在試算表新增一欄的動作。
/// 所有欄位都預先帶入上次的數字，只需改有變動的項目；下方即時顯示更新後的淨值。
struct UpdateSheet: View {
    @Environment(\.portfolio) private var store
    @Environment(\.dismiss) private var dismiss

    let base: Snapshot?
    /// 使用中的帳戶，從 store 即時讀取（在這個畫面新增信用卡會馬上出現）
    private var accounts: [Account] { store.activeAccounts }

    @State private var date = Date.now
    @State private var quoteDrafts: [Quote: String]
    @State private var amountDrafts: [UUID: String]
    @FocusState private var focus: Field?
    /// 更新到一半想到少一個帳戶：在這個畫面直接新增，已填的數字不會動
    @State private var addingCategory: AssetCategory?

    // 持股
    @State private var positionDrafts: [UUID: [PositionDraft]]
    @State private var stockPrices: [String: Double]
    @State private var stockSources: [String: String] = [:]

    // 自動帶入報價
    @State private var live: LiveQuotes?
    @State private var fetchState: FetchState = .idle
    @State private var refreshToken = 0
    /// 使用者親手改過的報價，自動帶入時不會覆蓋
    @State private var userEditedQuotes: Set<Quote> = []

    enum FetchState: Equatable { case idle, loading, done, failed }

    enum Field: Hashable {
        case quote(Quote)
        case account(UUID)
    }

    init(base: Snapshot?, accounts: [Account]) {
        self.base = base
        _quoteDrafts = State(initialValue: Dictionary(uniqueKeysWithValues: Quote.allCases.map { q in
            (q, base?.quotes[q].map { Fmt.number($0) } ?? "")
        }))
        _amountDrafts = State(initialValue: Dictionary(uniqueKeysWithValues: accounts.map { a in
            (a.id, base?.amounts[a.id].map { Fmt.number($0, digits: a.inputFractionDigits) } ?? "")
        }))
        _positionDrafts = State(initialValue: Dictionary(uniqueKeysWithValues: accounts.filter(\.isPortfolio).map { a in
            (a.id, (base?.holdings[a.id] ?? []).map {
                PositionDraft(symbol: $0.symbol, name: $0.name, sharesText: Fmt.number($0.shares, digits: 0...4))
            })
        }))
        _stockPrices = State(initialValue: base?.stockPrices ?? [:])
    }

    // MARK: 計算

    private var draft: Snapshot {
        var quotes = base?.quotes ?? [:]
        for (q, s) in quoteDrafts { if let v = Fmt.parse(s) { quotes[q] = v } }
        var amounts = base?.amounts ?? [:]
        for (id, s) in amountDrafts {
            if let v = Fmt.parse(s) { amounts[id] = v } else if s.isEmpty { amounts[id] = nil }
        }
        var holdings = base?.holdings ?? [:]
        for (id, drafts) in positionDrafts {
            holdings[id] = drafts.compactMap { d in
                guard let shares = Fmt.parse(d.sharesText), shares > 0 else { return nil }
                return Position(symbol: d.symbol, name: d.name, shares: shares)
            }
        }
        let held = Set(holdings.values.flatMap { $0.map(\.symbol) })
        return Snapshot(date: date, quotes: quotes, amounts: amounts,
                        holdings: holdings.filter { !$0.value.isEmpty },
                        stockPrices: stockPrices.filter { held.contains($0.key) })
    }

    /// 持股有變動的檔數（股數改變、新增或移除）
    private var changedPositionCount: Int {
        positionDrafts.reduce(0) { total, entry in
            let before = Dictionary(uniqueKeysWithValues: (base?.holdings[entry.key] ?? []).map { ($0.symbol, $0.shares) })
            let after = Dictionary(uniqueKeysWithValues: entry.value.map { ($0.symbol, Fmt.parse($0.sharesText) ?? 0) })
            let symbols = Set(before.keys).union(after.keys)
            return total + symbols.filter { (before[$0] ?? 0) != (after[$0] ?? 0) }.count
        }
    }

    private var allDraftSymbols: [String] {
        Array(Set(positionDrafts.values.flatMap { $0.map(\.symbol) }))
    }

    private func isChanged(_ field: Field) -> Bool {
        switch field {
        case .quote(let q): Fmt.parse(quoteDrafts[q] ?? "") != base?.quotes[q]
        case .account(let id): Fmt.parse(amountDrafts[id] ?? "") != base?.amounts[id]
        }
    }

    private var orderedFields: [Field] {
        Quote.allCases.map { .quote($0) }
            + AssetCategory.allCases.flatMap { c in accounts.filter { $0.category == c }.map { .account($0.id) } }
    }

    /// 欄位目前的數字是否就是自動帶入的報價
    private func isLive(_ q: Quote) -> Bool {
        guard !userEditedQuotes.contains(q), let v = live?.values[q] else { return false }
        return Fmt.parse(quoteDrafts[q] ?? "") == rounded(v, q)
    }

    private func rounded(_ v: Double, _ q: Quote) -> Double {
        let p = pow(10, Double(q.liveFractionDigits))
        return (v * p).rounded() / p
    }

    /// 自動帶入的報價不算「使用者修改」
    private var changedCount: Int {
        orderedFields.filter { f in
            if case .quote(let q) = f, isLive(q) { return false }
            return isChanged(f)
        }.count + changedPositionCount
    }

    private func fetchQuotes() async {
        fetchState = .loading
        async let quoteResult = QuoteService.fetch(for: date)
        async let stockResult: Void = fetchStockPrices()
        let (result, _) = await (quoteResult, stockResult)
        guard !Task.isCancelled else { return }
        for q in Quote.allCases where !userEditedQuotes.contains(q) {
            if let v = result.values[q] {
                quoteDrafts[q] = Fmt.number(rounded(v, q), digits: 0...q.liveFractionDigits)
            } else {
                // 取不到的報價回到上次的數字（例如換日期後查無資料）
                quoteDrafts[q] = base?.quotes[q].map { Fmt.number($0) } ?? ""
            }
        }
        withAnimation(.snappy) {
            live = result
            fetchState = result.values.isEmpty ? .failed : .done
        }
    }

    /// 今天用即時股價，補登過去日期用當天收盤價；取不到的沿用上次
    private func fetchStockPrices() async {
        let symbols = allDraftSymbols
        guard !symbols.isEmpty else { return }
        if Calendar.current.isDateInToday(date) {
            let r = await StockService.quotes(symbols)
            for (s, q) in r.quotes { stockPrices[s] = q.price; stockSources[s] = q.source }
        } else {
            let closes = await StockService.closes(symbols, on: date)
            for (s, p) in closes { stockPrices[s] = p; stockSources[s] = "當日收盤" }
        }
        for s in symbols where stockSources[s] == nil && stockPrices[s] != nil {
            stockSources[s] = "沿用上次"
        }
    }

    private var hasInvalidInput: Bool {
        quoteDrafts.values.contains { !$0.isEmpty && Fmt.parse($0) == nil }
            || amountDrafts.values.contains { !$0.isEmpty && Fmt.parse($0) == nil }
            || positionDrafts.values.joined().contains { !$0.sharesText.isEmpty && Fmt.parse($0.sharesText) == nil }
    }

    private func move(_ offset: Int) {
        guard let focus, let i = orderedFields.firstIndex(of: focus) else { return }
        let j = i + offset
        self.focus = orderedFields.indices.contains(j) ? orderedFields[j] : nil
    }

    // MARK: 介面

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $date, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    if store.hasSnapshot(on: date) {
                        Label("這天已有一筆紀錄，儲存後會覆蓋。", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else if let base {
                        Text("已帶入 \(base.date.formatted(.dateTime.month(.defaultDigits).day())) 的數字，只要修改有變動的欄位。按 Return 跳到下一格。")
                    }
                }

                Section {
                    ForEach(Quote.allCases) { q in
                        DraftRow(title: q.title,
                                 icon: AnyView(Image(systemName: q.symbol).foregroundStyle(.secondary).frame(width: 32)),
                                 unit: q.unit,
                                 text: binding(for: q),
                                 previous: base?.quotes[q],
                                 previousDigits: 0...8,
                                 isChanged: isChanged(.quote(q)) && !isLive(q),
                                 caption: nil,
                                 liveTag: isLive(q) ? liveTag(for: q) : nil)
                            .focused($focus, equals: .quote(q))
                            .onSubmit { move(1) }
                    }
                } header: {
                    quoteHeader
                } footer: {
                    quoteFooter
                }

                ForEach(AssetCategory.allCases) { cat in
                    let items = accounts.filter { $0.category == cat }
                    if !items.isEmpty || cat.isLiability {
                        Section {
                            ForEach(items.filter(\.isPortfolio)) { a in
                                PortfolioDraftEditor(
                                    account: a,
                                    positions: positionsBinding(for: a.id),
                                    previous: base?.holdings[a.id] ?? [],
                                    prices: stockPrices,
                                    priceSources: stockSources,
                                    cashRow: AnyView(cashRow(for: a)),
                                    onAdd: { position, price in
                                        withAnimation {
                                            positionDrafts[a.id, default: []].append(PositionDraft(
                                                symbol: position.symbol, name: position.name,
                                                sharesText: Fmt.number(position.shares, digits: 0...4)))
                                        }
                                        stockPrices[position.symbol] = price
                                        stockSources[position.symbol] = "即時"
                                    })
                            }
                            if cat == .stocks {
                                ConvertToPortfolioPrompt(accounts: items.filter { !$0.isPortfolio })
                            }
                            ForEach(items.filter { !$0.isPortfolio }) { a in
                                DraftRow(title: a.name,
                                         icon: AnyView(AccountAvatar(account: a, size: 32)),
                                         unit: a.inputUnit,
                                         text: binding(for: a.id),
                                         previous: base?.amounts[a.id],
                                         previousDigits: a.inputFractionDigits,
                                         isChanged: isChanged(.account(a.id)),
                                         caption: caption(for: a),
                                         emptyMeaning: cat.isLiability ? "本期無帳單" : nil)
                                    .focused($focus, equals: .account(a.id))
                                    .onSubmit { move(1) }
                            }
                            Button {
                                addingCategory = cat
                            } label: {
                                Label(cat.addTitle, systemImage: "plus.circle.fill")
                                    .foregroundStyle(cat.tint)
                            }
                            .buttonStyle(.borderless)
                        } header: {
                            Text(cat.title)
                        } footer: {
                            if cat.isLiability {
                                Text("輸入本期應繳金額，會自動從淨值扣除。沒帳單就按「無帳單」；不再使用的卡可到「帳戶」頁封存。")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom, spacing: 0) { summaryBar }
            .navigationTitle("更新資產")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }
                        .disabled(hasInvalidInput)
                        .keyboardShortcut("s", modifiers: .command)
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    Button { move(1) } label: { Image(systemName: "chevron.down") }
                    Spacer()
                    Button("完成") { focus = nil }.bold()
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 640, minHeight: 640, idealHeight: 760)
        #endif
        .interactiveDismissDisabled(changedCount > 0)
        .sheet(item: $addingCategory) { cat in
            AccountEditor(category: cat) { account in
                // 新增後直接跳到那個帳戶的金額欄位
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus = .account(account.id) }
            }
            .environment(\.portfolio, store)
        }
        .task(id: "\(Fmt.day(date))-\(refreshToken)") {
            guard store.autoFetchQuotes || refreshToken > 0 else { return }
            await fetchQuotes()
        }
    }

    // MARK: 報價狀態

    private var quoteHeader: some View {
        HStack(spacing: 8) {
            Text("市場報價")
            Spacer()
            switch fetchState {
            case .loading:
                ProgressView().controlSize(.small)
                Text("取得最新報價中…").textCase(nil)
            case .done, .failed, .idle:
                if fetchState == .failed {
                    Label("無法取得，沿用上次", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange).textCase(nil)
                } else if let live, fetchState == .done {
                    Text(live.isHistorical ? "\(date.formatted(.dateTime.month(.defaultDigits).day())) 當日報價"
                                           : "更新於 \(live.fetchedAt.formatted(date: .omitted, time: .shortened))")
                        .textCase(nil)
                }
                Button {
                    userEditedQuotes = []
                    refreshToken += 1
                } label: {
                    Label(fetchState == .idle ? "取得最新報價" : "重新取得", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .textCase(nil)
                .help("從網路取得最新匯率與幣價，會覆蓋報價欄位")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var quoteFooter: some View {
        if let live, fetchState != .loading {
            if !live.missing.isEmpty, fetchState == .done {
                Text("\(live.missing.map(\.title).joined(separator: "、")) 無法取得，沿用上次的數字。")
            } else if live.isHistorical {
                Text("補登過去日期時，使用當天的每日收盤報價。")
            } else if fetchState == .done {
                Text("匯率為國際中間價，與銀行牌告可能略有差距；有需要可直接修改。")
            }
        }
    }

    private func liveTag(for q: Quote) -> String {
        let source = live?.sources[q] ?? ""
        return live?.isHistorical == true ? "當日 · \(source)" : "即時 · \(source)"
    }

    private var summaryBar: some View {
        let newNet = store.netWorth(draft)
        let oldNet = base.map(store.netWorth) ?? 0
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("更新後淨資產")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                MoneyText(value: newNet)
                    .font(.title2.weight(.bold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if base != nil, abs(newNet - oldNet) >= 0.5 { DeltaBadge(delta: newNet - oldNet, base: oldNet) }
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.groupedBackground)
        .overlay(alignment: .top) { Divider() }
        .animation(.snappy, value: changedCount)
    }

    private var summaryText: String {
        let liveCount = Quote.allCases.filter(isLive).count
        return switch (changedCount, liveCount) {
        case (0, 0): "尚未修改"
        case (0, _): "已自動帶入 \(liveCount) 個報價"
        case (_, 0): "已修改 \(changedCount) 項"
        default: "已修改 \(changedCount) 項 · 自動帶入 \(liveCount) 個報價"
        }
    }

    private func caption(for a: Account) -> String? {
        guard case .holding = a.valuation else { return nil }
        let v = store.nativeValue(of: a, in: draft) ?? 0
        return store.hideAmounts ? nil : "≈ \(Fmt.money(v, a.currency))"
    }

    private func binding(for q: Quote) -> Binding<String> {
        Binding(get: { quoteDrafts[q] ?? "" }, set: {
            quoteDrafts[q] = $0
            userEditedQuotes.insert(q)
        })
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(get: { amountDrafts[id] ?? "" }, set: { amountDrafts[id] = $0 })
    }

    private func positionsBinding(for id: UUID) -> Binding<[PositionDraft]> {
        Binding(get: { positionDrafts[id] ?? [] }, set: { positionDrafts[id] = $0 })
    }

    private func cashRow(for a: Account) -> some View {
        let hasPositions = !(positionDrafts[a.id] ?? []).isEmpty
        let neverSetUp = (base?.holdings[a.id] ?? []).isEmpty
        return DraftRow(title: "帳戶現金",
                        icon: AnyView(Image(systemName: "banknote").foregroundStyle(.secondary).frame(width: 32)),
                        unit: a.currency.rawValue,
                        text: binding(for: a.id),
                        previous: base?.amounts[a.id],
                        previousDigits: a.inputFractionDigits,
                        isChanged: isChanged(.account(a.id)),
                        caption: neverSetUp && !hasPositions ? "目前是原本的總金額；加入持股後請改成帳戶裡的現金" : nil)
            .focused($focus, equals: .account(a.id))
    }

    private func save() {
        var s = draft
        s.amounts = s.amounts.filter { id, _ in accounts.contains { $0.id == id } }
        s.holdings = s.holdings.filter { id, _ in accounts.contains { $0.id == id } }
        withAnimation { store.save(s) }
        dismiss()
    }
}

// MARK: - 單一輸入列

private struct DraftRow: View {
    let title: String
    let icon: AnyView
    let unit: String
    @Binding var text: String
    let previous: Double?
    let previousDigits: ClosedRange<Int>
    let isChanged: Bool
    let caption: String?
    var liveTag: String? = nil
    /// 欄位留空代表的意思（例如信用卡「本期無帳單」）；有設定時會顯示一鍵清空按鈕
    var emptyMeaning: String? = nil

    private var parsed: Double? { Fmt.parse(text) }
    private var isInvalid: Bool { !text.isEmpty && parsed == nil }

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    if isChanged {
                        Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                subtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)

            if let emptyMeaning, !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Label("無帳單", systemImage: "xmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("標記為\(emptyMeaning)")
            } else if isChanged, previous != nil {
                Button {
                    text = previous.map { Fmt.number($0, digits: previousDigits) } ?? ""
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("還原為上次的數字")
            }

            TextField(title, text: $text, prompt: Text(emptyMeaning ?? (previous == nil ? "輸入數字" : "")))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 170)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #else
                .textFieldStyle(.roundedBorder)
                #endif
                .foregroundStyle(isInvalid ? .red : .primary)

            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
        }
        .animation(.snappy(duration: 0.2), value: isChanged)
    }

    @ViewBuilder private var subtitle: some View {
        if isInvalid {
            Text("無法辨識的數字").foregroundStyle(.red)
        } else if let previous {
            HStack(spacing: 6) {
                Text("上次 \(Fmt.number(previous, digits: previousDigits))")
                if text.isEmpty, let emptyMeaning {
                    Text(emptyMeaning).fontWeight(.semibold).foregroundStyle(Color.accentColor)
                } else if isChanged, let parsed {
                    // 上次金額太小或變動超過 ±100% 時，百分比沒有參考價值，改顯示差額
                    let diff = parsed - previous
                    let meaningful = abs(previous) >= 1000 && abs(diff / previous) <= 1
                    Text(meaningful ? Fmt.percent(diff / abs(previous))
                                    : (diff > 0 ? "+" : "−") + Fmt.number(abs(diff), digits: previousDigits))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
                if let caption { Text(caption) }
                if let liveTag {
                    Label(liveTag, systemImage: "antenna.radiowaves.left.and.right")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
        } else {
            Text(emptyMeaning != nil && text.isEmpty ? "新增的卡 · 輸入本期應繳金額" : "新帳戶")
        }
    }
}
