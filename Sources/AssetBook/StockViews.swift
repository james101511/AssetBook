import SwiftUI

// MARK: - 代號標籤

struct TickerBadge: View {
    let symbol: String
    var size: CGFloat = 34

    var body: some View {
        let text = StockService.displaySymbol(symbol)
        Text(text)
            .font(.system(size: size * (text.count >= 5 ? 0.24 : text.count == 4 ? 0.28 : 0.32),
                          weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(.horizontal, 2)
            .foregroundStyle(AssetCategory.stocks.tint)
            .frame(width: size, height: size)
            .background(AssetCategory.stocks.tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityLabel(text)
    }
}

// MARK: - 改成持股明細的提示

/// 股票帳戶還在「輸入總金額」時顯示，一鍵改成持股明細
struct ConvertToPortfolioPrompt: View {
    @Environment(\.portfolio) private var store
    let accounts: [Account]

    var body: some View {
        if !accounts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("\(accounts.map(\.name).joined(separator: "、")) 目前記的是總金額，股價變動不會自動反映。改成持股明細後，填入每檔股票的股數即可。")
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(AssetCategory.stocks.tint)
                }
                .font(.callout)
                HStack {
                    ForEach(accounts) { a in
                        Button {
                            withAnimation { store.convertToPortfolio(a) }
                        } label: {
                            Label(accounts.count > 1 ? "「\(a.name)」改成持股明細" : "改成持股明細", systemImage: "list.bullet.rectangle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                Text("過去的紀錄不會改變。").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - 持股明細（帳戶頁）

struct PositionsSection: View {
    @Environment(\.portfolio) private var store
    let account: Account
    let snapshot: Snapshot

    var body: some View {
        let positions = snapshot.holdings[account.id] ?? []
        let hasLive = store.liveUpdatedAt != nil
        Section {
            if positions.isEmpty {
                Text("還沒有持股。按「調整持股」加入股票代號與股數，之後股價變動會自動反映。")
                    .foregroundStyle(.secondary)
            }
            ForEach(positions) { p in
                let live = store.liveStocks[p.symbol]
                let price = live?.price ?? snapshot.stockPrices[p.symbol] ?? 0
                HStack(spacing: 12) {
                    TickerBadge(symbol: p.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).lineLimit(1)
                        Text("\(Fmt.number(p.shares, digits: 0...4)) 股 × \(Fmt.number(price, digits: 0...2))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        MoneyText(value: p.shares * price, currency: account.currency).fontWeight(.medium)
                        if let prev = live?.previousClose, prev > 0 {
                            DeltaText(delta: price - prev, base: prev, showPercentOnly: true).font(.caption)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if let cash = snapshot.amounts[account.id], cash != 0 {
                HStack(spacing: 12) {
                    Image(systemName: "banknote")
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text("帳戶現金")
                    Spacer()
                    MoneyText(value: cash, currency: account.currency)
                }
            }
            Button {
                store.isUpdating = true
            } label: {
                Label("調整持股", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
        } header: {
            HStack {
                Text("持股")
                Spacer()
                Text(hasLive ? "即時股價 · 右側為今日漲跌" : "紀錄時的股價")
                    .textCase(nil)
            }
        } footer: {
            Text("有買賣時，在「更新資產」裡修改股數；平常不用動。")
        }
    }
}

// MARK: - 更新資產：持股編輯

struct PositionDraft: Identifiable, Hashable {
    var id: String { symbol }
    var symbol: String
    var name: String
    var sharesText: String
}

/// 一個持股帳戶在「更新資產」裡的欄位：每檔股數、新增持股、帳戶現金
struct PortfolioDraftEditor: View {
    let account: Account
    @Binding var positions: [PositionDraft]
    let previous: [Position]
    let prices: [String: Double]
    let priceSources: [String: String]
    let cashRow: AnyView
    let onAdd: (Position, Double) -> Void

    @State private var searching = false

    var body: some View {
        HStack(spacing: 12) {
            AccountAvatar(account: account, size: 32)
            Text(account.name).font(.headline)
            Spacer()
            Text("\(positions.count) 檔")
                .font(.caption).foregroundStyle(.secondary)
        }

        ForEach($positions) { $draft in
            let before = previous.first { $0.symbol == draft.symbol }?.shares
            let shares = Fmt.parse(draft.sharesText)
            let price = prices[draft.symbol]
            HStack(spacing: 12) {
                TickerBadge(symbol: draft.symbol, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(draft.name).lineLimit(1)
                        if shares != before {
                            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                        }
                    }
                    Group {
                        if let price {
                            Text("× \(Fmt.number(price, digits: 0...2))\(priceSources[draft.symbol].map { " · \($0)" } ?? "")")
                            + Text(shares.map { " ≈ \(Fmt.money($0 * price, account.currency))" } ?? "")
                        } else {
                            Text("取得股價中…")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 8)
                TextField("股數", text: $draft.sharesText, prompt: Text("股數"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 130)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #else
                    .textFieldStyle(.roundedBorder)
                    #endif
                Text("股").font(.caption).foregroundStyle(.secondary).frame(width: 18, alignment: .leading)
                Button {
                    withAnimation { positions.removeAll { $0.symbol == draft.symbol } }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("全部賣出／移除這檔")
            }
        }

        Button {
            searching = true
        } label: {
            Label("新增持股", systemImage: "plus.circle.fill")
                .foregroundStyle(AssetCategory.stocks.tint)
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $searching) {
            SecuritySearchSheet(currency: account.currency, existing: Set(positions.map(\.symbol)), onAdd: onAdd)
        }

        cashRow
    }
}

// MARK: - 搜尋並新增持股

struct SecuritySearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currency: Currency
    let existing: Set<String>
    let onAdd: (Position, Double) -> Void

    @State private var query = ""
    @State private var results: [SecurityResult] = []
    @State private var searching = false
    @State private var selected: SecurityResult?
    @State private var quote: StockQuote?
    @State private var loadingQuote = false
    @State private var sharesText = ""
    @FocusState private var sharesFocused: Bool

    private var market: String {
        switch currency {
        case .twd: "台股"
        case .usd: "美股"
        case .jpy: "日股"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selected { detail(selected) } else { searchList }
            }
            .navigationTitle(selected == nil ? "新增持股" : StockService.displaySymbol(selected!.symbol))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if selected != nil {
                        Button("返回") { withAnimation { selected = nil; quote = nil; sharesText = "" } }
                    } else {
                        Button("取消") { dismiss() }
                    }
                }
                if let selected {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("加入") { add(selected) }
                            .disabled(!canAdd)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    private var searchList: some View {
        List {
            Section {
                TextField("搜尋", text: $query, prompt: Text(currency == .twd ? "代號或名稱，例如 2330、台積電、0050" : "代號或名稱，例如 NVDA、VOO、Apple"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
            } footer: {
                Text("只顯示\(market)（這個帳戶以\(currency.name)計價）。")
            }

            Section {
                if searching && results.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text("搜尋中…").foregroundStyle(.secondary) }
                } else if !query.isEmpty && results.isEmpty {
                    Text("找不到符合的\(market)").foregroundStyle(.secondary)
                }
                ForEach(results) { r in
                    Button {
                        select(r)
                    } label: {
                        HStack(spacing: 12) {
                            TickerBadge(symbol: r.symbol, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).foregroundStyle(.primary).lineLimit(1)
                                Text("\(StockService.displaySymbol(r.symbol)) · \(r.exchange)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if existing.contains(r.symbol) {
                                Text("已持有").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(existing.contains(r.symbol))
                }
            }
        }
        .task(id: query) {
            let q = query
            guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
            try? await Task.sleep(for: .milliseconds(350))   // 打字停下來再搜尋
            guard !Task.isCancelled else { return }
            searching = true
            let found = await StockService.search(q).filter { $0.currency == currency }
            guard !Task.isCancelled else { return }
            results = found
            searching = false
        }
    }

    private func detail(_ r: SecurityResult) -> some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    TickerBadge(symbol: r.symbol, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(quote?.name ?? r.name).font(.headline)
                        Text("\(StockService.displaySymbol(r.symbol)) · \(r.exchange)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("目前股價") {
                    if let quote {
                        Text("\(Fmt.money(quote.price, currency, digits: 2)) · \(quote.source)").monospacedDigit()
                    } else if loadingQuote {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("無法取得").foregroundStyle(.orange)
                    }
                }
            }
            Section {
                LabeledContent("股數") {
                    TextField("股數", text: $sharesText, prompt: Text("0"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($sharesFocused)
                        .frame(maxWidth: 160)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .onSubmit { if canAdd { add(r) } }
                }
                if let shares = Fmt.parse(sharesText), let quote {
                    LabeledContent("市值") {
                        Text(Fmt.money(shares * quote.price, currency)).fontWeight(.semibold).monospacedDigit()
                    }
                }
            } footer: {
                if currency == .twd {
                    Text("以「股」為單位：1 張 = 1,000 股，零股直接填股數。")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var canAdd: Bool {
        (Fmt.parse(sharesText) ?? 0) > 0 && quote != nil
    }

    private func select(_ r: SecurityResult) {
        withAnimation { selected = r }
        loadingQuote = true
        Task {
            quote = await StockService.quotes([r.symbol]).quotes[r.symbol]
            loadingQuote = false
            sharesFocused = true
        }
    }

    private func add(_ r: SecurityResult) {
        guard let shares = Fmt.parse(sharesText), shares > 0, let quote else { return }
        // 台股用搜尋結果的中文名稱，其他用報價來源的正式名稱
        let name = (currency == .twd || quote.name.isEmpty) ? r.name : quote.name
        onAdd(Position(symbol: r.symbol, name: name, shares: shares), quote.price)
        dismiss()
    }
}
