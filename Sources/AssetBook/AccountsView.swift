import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - 帳戶列表

/// 「全部」：資產 − 負債 = 淨資產，加上每個分類一列摘要，點下去切到該分類。
/// 單一分類：分類小計＋該分類的帳戶（股票帳戶直接展開持股）。
struct AccountsView: View {
    @Environment(\.portfolio) private var store
    @Binding var filter: AccountsFilter
    /// iPhone／iPad 顯示頂端的分段選單；Mac 改用側邊欄切換
    var showsPicker = true

    @State private var adding: AssetCategory?
    @State private var editing: Account?
    @State private var showArchived = false

    var body: some View {
        Group {
            if filter.category == nil, let latest = store.latest {
                overviewScroll(latest: latest, prev: store.snapshot(before: latest))
            } else {
                categoryList
            }
        }
        .navigationTitle(showsPicker ? "帳戶" : filter.title)
        .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let cat = filter.category {
                    Button { adding = cat } label: { Label(cat.addTitle, systemImage: "plus") }
                        .help(cat.addTitle)
                } else {
                    Menu {
                        ForEach(AssetCategory.allCases) { cat in
                            Button(cat.title, systemImage: cat.symbol) { adding = cat }
                        }
                    } label: {
                        Label("新增", systemImage: "plus")
                    }
                    .help("新增帳戶或信用卡")
                }
                UpdateToolbarButton(store: store)
            }
        }
        .sheet(item: $adding) { cat in
            AccountEditor(category: cat).environment(\.portfolio, store)
        }
        .sheet(item: $editing) { account in
            AccountEditor(account: account).environment(\.portfolio, store)
        }
    }

    private var categoryList: some View {
        List {
            if showsPicker {
                Section {
                    Picker("分類", selection: $filter.animation(.snappy)) {
                        ForEach(AccountsFilter.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            if let latest = store.latest, let cat = filter.category {
                categoryPage(cat, latest: latest, prev: store.snapshot(before: latest))
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: 全部

    private func overviewScroll(latest: Snapshot, prev: Snapshot?) -> some View {
        let cats = AssetCategory.allCases.filter { !store.activeAccounts(in: $0).isEmpty }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsPicker {
                    Picker("分類", selection: $filter.animation(.snappy)) {
                        ForEach(AccountsFilter.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Card { BalanceSummary(snapshot: latest, previous: prev) }

                Card {
                    CategoryTableHeader(previous: prev)
                    VStack(spacing: 0) {
                        ForEach(Array(cats.enumerated()), id: \.element.id) { i, cat in
                            if i > 0 { Divider().opacity(0.6) }
                            Button {
                                withAnimation(.snappy) { filter = AccountsFilter(cat) }
                            } label: {
                                CategorySummaryRow(category: cat, snapshot: latest, previous: prev)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("點分類查看帳戶明細，⌘1–⌘5 快速切換")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                if !store.archivedAccounts.isEmpty {
                    Card {
                        DisclosureGroup(isExpanded: $showArchived) {
                            VStack(spacing: 0) {
                                ForEach(store.archivedAccounts) { account in
                                    NavigationLink(value: account) {
                                        AccountRow(account: account, snapshot: latest, previous: nil)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu { actions(for: account) }
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Label("已封存（\(store.archivedAccounts.count)）", systemImage: "archivebox")
                                .foregroundStyle(.secondary)
                        }
                        Text("封存的帳戶不會出現在更新畫面，過去的紀錄會保留，淨資產歷史不受影響。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
    }

    // MARK: 單一分類

    @ViewBuilder private func categoryPage(_ cat: AssetCategory, latest: Snapshot, prev: Snapshot?) -> some View {
        let items = store.activeAccounts(in: cat)

        Section {
            CategoryOverview(category: cat, snapshot: latest, previous: prev)
        }

        if cat == .cash, !items.isEmpty {
            // 現金與存款分成子分類（銀行、交易所與穩定幣、現鈔與儲值）：
            // 子分類是一列，底下縮排列出它的帳戶，和股票頁的持股一樣
            Section {
                ForEach(CashGroup.allCases.filter { g in items.contains { $0.resolvedCashGroup == g } }) { g in
                    let group = items.filter { $0.resolvedCashGroup == g }
                    CashGroupRow(group: g, accounts: group, snapshot: latest, previous: prev)
                    accountRows(group, latest: latest, prev: prev, indent: 48)
                }
                Button {
                    adding = cat
                } label: {
                    Label(cat.addTitle, systemImage: "plus.circle.fill")
                        .foregroundStyle(cat.tint)
                }
                .buttonStyle(.borderless)
            } header: {
                if let prev {
                    Text("右側漲跌為與 \(prev.date.formatted(.dateTime.month(.defaultDigits).day())) 相比")
                        .textCase(nil)
                }
            }
        } else {
            Section {
                if items.isEmpty {
                    Text(cat.isLiability ? "還沒有信用卡。" : "這個分類還沒有帳戶。")
                        .foregroundStyle(.secondary)
                }
                accountRows(items, latest: latest, prev: prev)
                if cat == .stocks {
                    ConvertToPortfolioPrompt(accounts: items.filter { !$0.isPortfolio })
                }
                Button {
                    adding = cat
                } label: {
                    Label(cat.addTitle, systemImage: "plus.circle.fill")
                        .foregroundStyle(cat.tint)
                }
                .buttonStyle(.borderless)
            } header: {
                if let prev {
                    Text("右側漲跌為與 \(prev.date.formatted(.dateTime.month(.defaultDigits).day())) 相比")
                        .textCase(nil)
                }
            } footer: {
                if cat.isLiability {
                    Text("這期沒有帳單的卡，在「更新資產」時按「無帳單」即可，不必刪除。")
                } else if cat == .stocks, items.contains(where: \.isPortfolio) {
                    Text("持股顯示的是紀錄時的股價；即時股價請看總覽或帳戶明細。")
                }
            }
        }
    }

    @ViewBuilder private func accountRows(_ list: [Account], latest: Snapshot, prev: Snapshot?,
                                          indent: CGFloat = 0) -> some View {
        ForEach(list) { account in
            NavigationLink(value: account) {
                AccountRow(account: account, snapshot: latest, previous: prev, nested: indent > 0)
                    .padding(.leading, indent)
            }
            .contextMenu { actions(for: account) }
            .swipeActions(edge: .trailing) {
                Button("封存", systemImage: "archivebox") { store.setArchived(account, true) }
                    .tint(.gray)
                Button("編輯", systemImage: "pencil") { editing = account }
                    .tint(.accentColor)
            }
            // 股票帳戶直接展開持股
            if account.isPortfolio {
                ForEach(latest.holdings[account.id] ?? []) { p in
                    PositionLine(position: p, account: account, snapshot: latest)
                }
            }
        }
    }

    @ViewBuilder private func actions(for account: Account) -> some View {
        Button("編輯…", systemImage: "pencil") { editing = account }
        if account.isArchived {
            Button("取消封存", systemImage: "tray.and.arrow.up") { store.setArchived(account, false) }
        } else {
            Button("封存", systemImage: "archivebox") { store.setArchived(account, true) }
        }
    }
}

// MARK: - 「全部」裡的分類摘要列

/// 分類表的欄位標題：金額、佔比、和上一筆紀錄比的漲跌
private struct CategoryTableHeader: View {
    let previous: Snapshot?

    private var versus: String {
        previous.map { "vs \($0.date.formatted(.dateTime.month(.defaultDigits).day()))" } ?? ""
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                Text("分類")
                Spacer(minLength: 0)
                Text("金額").frame(width: 140, alignment: .trailing)
                Text("佔比").frame(width: 64, alignment: .trailing)
                Text(versus).frame(width: 110, alignment: .trailing)
                Color.clear.frame(width: 24, height: 1)
            }
            .frame(minWidth: 620)
            HStack {
                Text("分類")
                Spacer()
                Text(previous == nil ? "金額" : "金額 · 佔比 · \(versus)")
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}

private struct CategorySummaryRow: View {
    @Environment(\.portfolio) private var store
    let category: AssetCategory
    let snapshot: Snapshot
    let previous: Snapshot?

    var body: some View {
        let accounts = store.activeAccounts(in: category)
        let total = store.total(category, in: snapshot)
        let gross = store.grossAssets(snapshot)
        // 金額最大的 3 個帳戶
        let top = accounts.sorted { abs(store.value(of: $0, in: snapshot)) > abs(store.value(of: $1, in: snapshot)) }.prefix(3)

        let title = HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(category.title).font(.body.weight(.medium))
                HStack(spacing: 0) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { i, a in
                        AccountAvatar(account: a, size: 18)
                            .padding(1.5)
                            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(.leading, i == 0 ? 0 : -6)
                            .zIndex(Double(3 - i))
                    }
                    Text("\(accounts.count) 個\(category.isLiability ? "卡片" : "帳戶")")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .fixedSize()
                }
            }
        }

        let share = Group {
            if !category.isLiability, gross > 0 {
                Text((total / gross).formatted(.percent.precision(.fractionLength(0))))
            } else {
                Text("—")
            }
        }
        .foregroundStyle(.secondary)

        let change = Group {
            if let previous {
                let old = store.total(category, in: previous)
                if category.isLiability {
                    LiabilityChange(now: abs(total), before: abs(old))
                } else {
                    DeltaText(delta: total - old, base: old, showPercentOnly: true)
                }
            }
        }

        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                title
                Spacer(minLength: 8)
                MoneyText(value: abs(total)).font(.system(size: 17)).frame(width: 140, alignment: .trailing)
                share.font(.callout).monospacedDigit().frame(width: 64, alignment: .trailing)
                change.font(.callout).monospacedDigit().frame(width: 110, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .trailing)
            }
            .frame(minWidth: 620)
            HStack(spacing: 8) {
                title
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    MoneyText(value: abs(total)).font(.system(size: 17))
                    HStack(spacing: 8) {
                        if !category.isLiability, gross > 0 { share }
                        change
                    }
                    .font(.caption).monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - 分類頁頂部

private struct CategoryOverview: View {
    @Environment(\.portfolio) private var store
    let category: AssetCategory
    let snapshot: Snapshot
    let previous: Snapshot?

    var body: some View {
        let total = store.total(category, in: snapshot)
        let gross = store.grossAssets(snapshot)
        let count = store.activeAccounts(in: category).count
        VStack(alignment: .leading, spacing: 8) {
            Label(category.isLiability ? "本期應繳合計" : category.title, systemImage: category.symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(category.tint)
            MoneyText(value: abs(total))
                .font(.system(size: 32, weight: .regular))
            HStack(spacing: 10) {
                if let previous {
                    let old = store.total(category, in: previous)
                    if category.isLiability {
                        LiabilityChange(now: abs(total), before: abs(old))
                        Text("較 \(previous.date.formatted(.dateTime.month(.defaultDigits).day()))").foregroundStyle(.secondary)
                    } else {
                        DeltaBadge(delta: total - old, base: old)
                        Text("較 \(previous.date.formatted(.dateTime.month(.defaultDigits).day()))").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !category.isLiability, gross > 0 {
                    Text("佔總資產 \((total / gross).formatted(.percent.precision(.fractionLength(0)))) · \(count) 個帳戶")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(count) 張卡").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 6)
    }
}

/// 現金分頁裡的子分類列：和股票頁的「台股」「美股」一樣，底下縮排列出帳戶
private struct CashGroupRow: View {
    @Environment(\.portfolio) private var store
    let group: CashGroup
    let accounts: [Account]
    let snapshot: Snapshot
    let previous: Snapshot?

    var body: some View {
        let total = accounts.reduce(0) { $0 + store.value(of: $1, in: snapshot) }
        let old = previous.map { p in accounts.reduce(0) { $0 + store.value(of: $1, in: p) } }
        let cash = store.total(.cash, in: snapshot)
        HStack(spacing: 12) {
            Image(systemName: group.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title).font(.body.weight(.medium))
                Text("\(accounts.count) 個帳戶" + (cash > 0 ? " · 佔 \((total / cash).formatted(.percent.precision(.fractionLength(0))))" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                MoneyText(value: total).font(.title3.weight(.semibold))
                if let old {
                    DeltaText(delta: total - old, base: old, showPercentOnly: true).font(.caption)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// 負債的變化用中性色，帳單變多不是「漲」
private struct LiabilityChange: View {
    @Environment(\.portfolio) private var store
    let now: Double
    let before: Double

    var body: some View {
        let d = now - before
        Group {
            if abs(d) < 1 {
                Text("持平")
            } else if store.hideAmounts {
                Text(d > 0 ? "▲" : "▼")
            } else {
                Text("\(d > 0 ? "▲" : "▼") \(Fmt.money(abs(d), .twd))")
            }
        }
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

/// 股票分頁裡，帳戶下方展開的一檔持股
private struct PositionLine: View {
    @Environment(\.portfolio) private var store
    let position: Position
    let account: Account
    let snapshot: Snapshot

    var body: some View {
        let price = snapshot.stockPrices[position.symbol] ?? 0
        HStack(spacing: 10) {
            TickerBadge(symbol: position.symbol, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(position.name).font(.subheadline).lineLimit(1)
                Text("\(Fmt.number(position.shares, digits: 0...4)) 股 × \(Fmt.number(price, digits: 0...2))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            MoneyText(value: position.shares * price, currency: account.currency)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 48)
    }
}

// MARK: - 總覽：資產 − 負債 = 淨資產

private struct BalanceSummary: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let previous: Snapshot?

    var body: some View {
        let gross = store.grossAssets(snapshot)
        let debt = -store.total(.liability, in: snapshot)
        let net = store.netWorth(snapshot)
        let parts = AssetCategory.allCases.filter { !$0.isLiability }
            .map { ($0, max(store.total($0, in: snapshot), 0)) }
            .filter { $0.1 > 0 }

        VStack(alignment: .leading, spacing: 20) {
            // 淨資產是主角；資產與負債是它的組成
            VStack(alignment: .leading, spacing: 6) {
                Text("淨資產").font(.subheadline).foregroundStyle(.secondary)
                MoneyText(value: net)
                    .font(.system(size: 36, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let previous {
                    let old = store.netWorth(previous)
                    HStack(spacing: 8) {
                        DeltaBadge(delta: net - old, base: old)
                        Text("vs \(previous.date.formatted(.dateTime.month(.defaultDigits).day()))")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }

            HStack(alignment: .top, spacing: 0) {
                part("資產", gross)
                part("負債", debt, minus: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                // 資產分類比例
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(parts, id: \.0) { cat, v in
                            Rectangle().fill(cat.tint)
                                .frame(width: max(geo.size.width * v / gross - 2, 2))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 6)

                HStack(spacing: 16) {
                    ForEach(parts, id: \.0) { cat, v in
                        HStack(spacing: 6) {
                            Circle().fill(cat.tint).frame(width: 6, height: 6)
                            Text(cat.title).foregroundStyle(.secondary)
                            Text((v / gross).formatted(.percent.precision(.fractionLength(0))))
                                .monospacedDigit()
                        }
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
            }
        }
    }

    private func part(_ title: String, _ value: Double, minus: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if minus { Text("−").foregroundStyle(.tertiary) }
                MoneyText(value: value)
            }
            .font(.system(size: 20, weight: .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 帳戶列

struct AccountRow: View {
    @Environment(\.portfolio) private var store
    let account: Account
    let snapshot: Snapshot
    let previous: Snapshot?
    /// 縮排在子分類底下時，字和圖示都小一點、金額用次要色，讓子分類的小計更突出
    var nested = false

    var body: some View {
        let hasAmount = snapshot.amounts[account.id].map { $0 != 0 } ?? false
        let value = store.value(of: account, in: snapshot)

        HStack(spacing: 12) {
            AccountAvatar(account: account, size: nested ? 30 : 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(nested ? .subheadline : .body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if account.category.isLiability && !hasAmount {
                    Text("本期無帳單").foregroundStyle(.secondary)
                } else {
                    // 負債顯示為正的應繳金額，比較直覺
                    if nested {
                        MoneyText(value: value).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        MoneyText(value: account.category.isLiability ? abs(value) : value)
                            .fontWeight(.medium)
                    }
                }
                change.font(.caption)
            }
        }
        .padding(.vertical, 3)
    }

    /// 外幣與持有數量才顯示原幣金額；台幣帳戶只顯示備註
    private var subtitle: String? {
        if store.hideAmounts { return account.note.isEmpty ? nil : account.note }
        let amount = snapshot.amounts[account.id] ?? 0
        let native = store.nativeValue(of: account, in: snapshot) ?? 0
        var parts: [String] = []
        switch account.valuation {
        case .holding:
            parts.append("\(Fmt.number(amount, digits: 0...4)) \(account.inputUnit)")
        case .balance where account.currency != .twd:
            parts.append(Fmt.money(native, account.currency))
        case .balance:
            break
        case .portfolio:
            let n = snapshot.holdings[account.id]?.count ?? 0
            parts.append(n == 0 ? "尚未設定持股" : "\(n) 檔持股")
            if account.currency != .twd { parts.append(Fmt.money(native, account.currency)) }
        }
        if !account.note.isEmpty { parts.append(account.note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var change: some View {
        if let previous {
            let now = store.value(of: account, in: snapshot)
            let old = store.value(of: account, in: previous)
            if abs(now - old) < 1 {
                Text("持平").foregroundStyle(.tertiary)
            } else if abs(old) < 1 {
                Text("新增").foregroundStyle(.secondary)
            } else if account.category.isLiability {
                // 帳單變多不是「漲」，用中性色顯示應繳金額的變化
                let owed = abs(now), owedBefore = abs(old)
                Text("\(owed > owedBefore ? "▲" : "▼") \(abs((owed - owedBefore) / owedBefore).formatted(.percent.precision(.fractionLength(1))))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                DeltaText(delta: now - old, base: old, showPercentOnly: true)
            }
        }
    }
}

// MARK: - 帳戶明細

struct AccountDetailView: View {
    @Environment(\.portfolio) private var store
    @Environment(\.dismiss) private var dismiss
    let account: Account
    @State private var editing = false
    @State private var editingAmount = false

    /// 編輯後名稱等資料會更新，所以每次都從 store 取最新的
    private var current: Account { store.account(id: account.id) ?? account }

    private struct Row: Identifiable {
        let id: UUID
        let date: Date
        let amount: Double?
        let value: Double
        let delta: Double?
    }

    private var rows: [Row] {
        var result: [Row] = []
        var last: Double?
        for s in store.snapshots where s.amounts[account.id] != nil || last != nil {
            let v = abs(store.value(of: current, in: s))
            result.append(Row(id: s.id, date: s.date, amount: s.amounts[account.id], value: v,
                              delta: last.map { v - $0 }))
            last = v
        }
        return result.reversed()
    }

    var body: some View {
        let account = current
        List {
            Section {
                HStack(spacing: 14) {
                    AccountAvatar(account: account, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        // 會隨市場變動的帳戶顯示即時估值，和下方持股的即時股價一致
                        if let shown = (store.isMarketLinked(account) ? store.liveSnapshot : nil) ?? store.latest {
                            MoneyText(value: abs(store.value(of: account, in: shown)))
                                .font(.system(size: 30, weight: .regular))
                            if account.currency != .twd || account.valuation != .balance {
                                MoneyText(value: store.nativeValue(of: account, in: shown) ?? 0, currency: account.currency)
                                    .foregroundStyle(.secondary)
                            }
                            if shown.id == PortfolioStore.liveSnapshotID {
                                Label("即時估值", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.caption).foregroundStyle(.green)
                            }
                        }
                        if account.isArchived {
                            Label("已封存", systemImage: "archivebox").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)

                if rows.count > 1 {
                    Chart(rows.reversed()) { r in
                        LineMark(x: .value("日期", r.date), y: .value("金額", r.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(account.category.tint)
                        PointMark(x: .value("日期", r.date), y: .value("金額", r.value))
                            .foregroundStyle(account.category.tint)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXScale(range: .plotDimension(padding: 20))
                    .chartXAxis {
                        AxisMarks(values: rows.map(\.date)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), anchor: .top)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { v in
                            AxisGridLine()
                            AxisValueLabel { if let d = v.as(Double.self) { Text(store.hideAmounts ? "" : Fmt.wan(d)) } }
                        }
                    }
                    .frame(height: 180)
                    .padding(.vertical, 6)
                }
            }

            if account.isPortfolio, let latest = store.latest {
                PositionsSection(account: account, snapshot: latest)
            } else if account.category == .stocks, !account.isArchived {
                Section("持股") {
                    ConvertToPortfolioPrompt(accounts: [account])
                }
            }

            Section(account.category.isLiability ? "帳單紀錄" : "紀錄") {
                if !account.isPortfolio, !account.isArchived, store.latest != nil {
                    Button {
                        editingAmount = true
                    } label: {
                        Label(account.category.isLiability ? "輸入應繳金額" : "輸入金額", systemImage: "square.and.pencil")
                    }
                }
                ForEach(rows) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.date.formatted(.dateTime.year().month(.defaultDigits).day()))
                            if case .holding = account.valuation, let amount = r.amount, !store.hideAmounts {
                                Text("\(Fmt.number(amount)) \(account.inputUnit)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if account.category.isLiability && (r.amount ?? 0) == 0 {
                                Text("無帳單").foregroundStyle(.secondary)
                            } else {
                                MoneyText(value: r.value)
                            }
                            if let d = r.delta, abs(d) >= 1 {
                                if account.category.isLiability {
                                    Text(Fmt.signedMoney(d, .twd)).font(.caption).foregroundStyle(.secondary)
                                } else {
                                    DeltaText(delta: d, base: r.value - d).font(.caption)
                                }
                            }
                        }
                    }
                }
            }

            Section("資訊") {
                LabeledContent("分類", value: account.category.title)
                LabeledContent("幣別", value: account.currency.name)
                LabeledContent("計價方式", value: {
                    if case .holding(let q) = account.valuation { return "持有數量 × \(q.title)價格" }
                    if account.isPortfolio { return "持股明細（股數 × 即時股價）" }
                    return account.category.isLiability ? "輸入應繳金額" : "直接輸入餘額"
                }())
                if !account.note.isEmpty { LabeledContent("備註", value: account.note) }
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("編輯") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            AccountEditor(account: account).environment(\.portfolio, store)
        }
        .sheet(isPresented: $editingAmount) {
            AmountEditor(account: account).environment(\.portfolio, store)
        }
        .onChange(of: store.account(id: account.id) == nil) { _, deleted in
            if deleted { dismiss() }
        }
    }
}

// MARK: - 修改最新一筆紀錄中的金額

/// 直接修改某帳戶在最新紀錄中的金額（帳單、餘額或持有數量），不必走完整的更新流程
struct AmountEditor: View {
    @Environment(\.portfolio) private var store
    @Environment(\.dismiss) private var dismiss
    let account: Account
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("金額", text: $text, prompt: Text("0"))
                            .focused($focused)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                        Text(account.inputUnit).foregroundStyle(.secondary)
                    }
                } header: {
                    if let d = store.latest?.date {
                        Text("\(d.formatted(.dateTime.year().month().day())) 的紀錄")
                    }
                } footer: {
                    Text(account.category.isLiability ? "這期信用卡帳單的應繳金額；沒有帳單就填 0。" : "會更新最新一筆紀錄中這個帳戶的數字。")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(account.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") { save() }.disabled(Fmt.parse(text) == nil)
                }
            }
            .onAppear {
                if let v = store.latest?.amounts[account.id] {
                    text = Fmt.number(v, digits: account.inputFractionDigits).replacingOccurrences(of: ",", with: "")
                }
                focused = true
            }
        }
        #if os(macOS)
        .frame(width: 380, height: 260)
        #endif
    }

    private func save() {
        guard var s = store.latest, let v = Fmt.parse(text) else { return }
        s.amounts[account.id] = v
        store.save(s)
        dismiss()
    }
}

// MARK: - 新增／編輯帳戶

struct AccountEditor: View {
    @Environment(\.portfolio) private var store
    @Environment(\.dismiss) private var dismiss

    /// nil 表示新增
    private let account: Account?
    /// 新增後回傳新帳戶（例如從更新畫面新增信用卡時，自動跳到該欄位）
    private let onCreate: ((Account) -> Void)?

    @State private var name: String
    @State private var note: String
    @State private var category: AssetCategory
    @State private var currency: Currency
    @State private var holding: Quote?
    /// 股票帳戶：記錄每檔股數，股價自動更新
    @State private var usesPortfolio: Bool
    /// 現金子分類；nil 為自動判斷
    @State private var cashGroup: CashGroup?
    @State private var confirmDelete = false

    // 圖示
    @State private var draftID: UUID
    @State private var iconChoice: IconChoice
    @State private var domain: String
    @State private var tokenID: String
    @State private var region: String
    @State private var pendingImage: Data?
    @State private var pickingImage = false

    enum IconChoice: String, CaseIterable, Identifiable {
        case auto, website, token, flag, custom, monogram
        var id: Self { self }
        var title: String {
            switch self {
            case .auto: "自動"
            case .website: "網站圖示"
            case .token: "代幣"
            case .flag: "國旗"
            case .custom: "自訂圖片"
            case .monogram: "文字縮寫"
            }
        }
    }

    init(account: Account? = nil, category: AssetCategory = .cash, onCreate: ((Account) -> Void)? = nil) {
        self.account = account
        self.onCreate = onCreate
        _draftID = State(initialValue: account?.id ?? UUID())
        let suggested = account.map(IconCatalog.suggestion) ?? .monogram
        var choice = IconChoice.auto
        var domain = "", token = "bitcoin", region = IconCatalog.region(for: account?.currency ?? .twd)
        for icon in [suggested, account?.icon].compactMap({ $0 }) {
            switch icon {
            case .website(let d): domain = d
            case .token(let id): token = id
            case .flag(let r): region = r
            default: break
            }
        }
        switch account?.icon {
        case .website?: choice = .website
        case .token?: choice = .token
        case .flag?: choice = .flag
        case .custom?: choice = .custom
        case .monogram?: choice = .monogram
        case nil: choice = .auto
        }
        _iconChoice = State(initialValue: choice)
        _domain = State(initialValue: domain)
        _tokenID = State(initialValue: token)
        _region = State(initialValue: region)
        _name = State(initialValue: account?.name ?? "")
        _note = State(initialValue: account?.note ?? "")
        _category = State(initialValue: account?.category ?? category)
        _currency = State(initialValue: account?.currency ?? .twd)
        _usesPortfolio = State(initialValue: account.map(\.isPortfolio) ?? (category == .stocks))
        _cashGroup = State(initialValue: account?.cashGroup)
        if case .holding(let q) = account?.valuation {
            _holding = State(initialValue: q)
        } else {
            _holding = State(initialValue: nil)
        }
    }

    private var isNew: Bool { account == nil }

    private var normalizedDomain: String {
        var d = domain.trimmingCharacters(in: .whitespaces).lowercased()
        for prefix in ["https://", "http://"] where d.hasPrefix(prefix) { d.removeFirst(prefix.count) }
        return String(d.split(separator: "/").first ?? "")
    }

    private var resolvedIcon: AccountIcon? {
        switch iconChoice {
        case .auto: nil
        case .website: normalizedDomain.isEmpty ? nil : .website(domain: normalizedDomain)
        case .token: .token(id: tokenID)
        case .flag: .flag(region: region)
        case .custom: (pendingImage != nil || account?.icon == .custom) ? .custom : nil
        case .monogram: .monogram
        }
    }

    /// 用目前填的內容組出帳戶，給頭像預覽與自動配對使用
    private func draftAccount(icon: AccountIcon?) -> Account {
        let liability = category.isLiability
        return Account(id: draftID, name: trimmedName.isEmpty ? category.title : trimmedName, note: note,
                       category: category,
                       currency: account?.currency ?? ((holding == nil || liability) ? currency : .usd),
                       valuation: account?.valuation ?? (liability ? .balance
                           : (category == .stocks && usesPortfolio) ? .portfolio
                           : (holding.map { .holding(quote: $0) } ?? .balance)),
                       icon: icon)
    }

    private var iconSection: some View {
        Section {
            HStack(spacing: 16) {
                AccountAvatar(account: draftAccount(icon: resolvedIcon), size: 56,
                              preview: iconChoice == .custom ? pendingImage.flatMap(PlatformImage.init(data:)) : nil)
                Picker("圖示", selection: $iconChoice) {
                    ForEach(IconChoice.allCases) { Text($0.title).tag($0) }
                }
            }
            switch iconChoice {
            case .website:
                TextField("網站", text: $domain, prompt: Text("例如：www.esunbank.com"))
                    .autocorrectionDisabled()
                Button("重新下載圖示") {
                    IconLoader.shared.refresh(.website(domain: normalizedDomain), accountID: draftID)
                }
                .disabled(normalizedDomain.isEmpty)
            case .token:
                Picker("代幣", selection: $tokenID) {
                    ForEach(IconCatalog.tokens, id: \.id) { Text($0.symbol).tag($0.id) }
                }
            case .flag:
                Picker("國旗", selection: $region) {
                    ForEach(IconCatalog.flags, id: \.region) { f in
                        Text("\(IconCatalog.flagEmoji(f.region)) \(f.name)").tag(f.region)
                    }
                }
            case .custom:
                Button(pendingImage == nil && account?.icon != .custom ? "選擇圖片…" : "更換圖片…") { pickingImage = true }
            case .auto, .monogram:
                EmptyView()
            }
        } header: {
            Text("圖示")
        } footer: {
            switch iconChoice {
            case .auto:
                Text("依名稱自動配對：\(IconCatalog.describe(IconCatalog.suggestion(for: draftAccount(icon: nil))))")
            case .website:
                Text("從銀行或交易所網站下載圖示並存在本機。圖示不清楚的話，可以改用自訂圖片。")
            case .custom:
                Text("建議使用正方形圖片，例如從 App Store 存下的 App 圖示。")
            default:
                EmptyView()
            }
        }
        .fileImporter(isPresented: $pickingImage, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get() else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            pendingImage = try? Data(contentsOf: url)
        }
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名稱", text: $name, prompt: Text(category.namePrompt))
                    TextField("備註", text: $note, prompt: Text(category.isLiability ? "選填，例如：每月 15 號結帳" : "選填"))
                }

                Section {
                    Picker("分類", selection: $category) {
                        ForEach(AssetCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    if category == .cash {
                        Picker("子分類", selection: $cashGroup) {
                            Text("自動").tag(CashGroup?.none)
                            ForEach(CashGroup.allCases) { Label($0.title, systemImage: $0.symbol).tag(CashGroup?.some($0)) }
                        }
                    }
                    if category == .stocks && (isNew || account?.valuation == .balance) {
                        Picker("計價方式", selection: $usesPortfolio) {
                            Text("持股明細（自動更新股價）").tag(true)
                            Text("輸入總金額").tag(false)
                        }
                    }
                    if isNew {
                        if !category.isLiability && category != .stocks {
                            Picker("計價方式", selection: $holding) {
                                Text("輸入餘額").tag(Quote?.none)
                                ForEach(Quote.holdable) { q in
                                    Text("持有 \(q.assetSymbol ?? "") 數量").tag(Quote?.some(q))
                                }
                            }
                        }
                        if holding == nil || category.isLiability {
                            Picker("幣別", selection: $currency) {
                                ForEach(Currency.allCases) { Text("\($0.name)（\($0.rawValue)）").tag($0) }
                            }
                        }
                    } else if let account {
                        LabeledContent("幣別", value: account.currency.name)
                        if !(category == .stocks && account.valuation == .balance) {
                            LabeledContent("計價方式", value: account.isPortfolio ? "持股明細"
                                           : holding.map { "持有 \($0.assetSymbol ?? "") 數量" } ?? "輸入餘額")
                        }
                    }
                } footer: {
                    if category == .stocks && usesPortfolio && account?.valuation == .balance {
                        Text("改成持股明細後，過去的紀錄不變。下次「更新資產」時加入股票代號與股數，股價就會自動更新。")
                    } else if category == .stocks && usesPortfolio && isNew {
                        Text("記錄每檔股票的股數，市值會依即時股價自動計算。股數只有買賣時才需要改。")
                    } else if !isNew {
                        Text("幣別與計價方式建立後無法更改，以免影響過去的紀錄。")
                    } else if category.isLiability {
                        Text("每次更新時輸入本期應繳金額，計算淨值時會自動扣除。沒有帳單的那期留空即可。")
                    } else if holding != nil {
                        Text("每次更新時輸入持有數量，App 會自動乘上當時的價格。")
                    } else {
                        Text("每次更新時輸入帳戶餘額。")
                    }
                }

                iconSection

                if let account {
                    Section {
                        Button(account.isArchived ? "取消封存" : "封存") {
                            store.setArchived(account, !account.isArchived)
                            dismiss()
                        }
                        Button("刪除", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("封存：不再出現在更新畫面，但保留過去的紀錄。\n刪除：連同過去所有紀錄一起移除，淨資產歷史會跟著改變。")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? category.addTitle : "編輯「\(account?.name ?? "")」")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "新增" : "完成") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("刪除「\(account?.name ?? "")」？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("刪除帳戶與所有紀錄", role: .destructive) {
                    if let account { store.delete(account) }
                    dismiss()
                }
                if let account, !account.isArchived {
                    Button("改為封存") {
                        store.setArchived(account, true)
                        dismiss()
                    }
                }
            } message: {
                let count = account.map(store.recordCount) ?? 0
                Text(count > 0
                     ? "這個帳戶出現在 \(count) 筆紀錄中，刪除後這些金額也會移除，無法復原。如果只是不再使用，建議改為封存。"
                     : "這個動作無法復原。")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: isNew ? 380 : 460)
        #endif
    }

    private func save() {
        if iconChoice == .custom, let pendingImage {
            try? IconLoader.shared.setCustom(pendingImage, accountID: draftID)
        }
        if var a = account {
            a.name = trimmedName
            a.note = note
            a.category = category
            a.cashGroup = category == .cash ? cashGroup : nil
            a.icon = resolvedIcon
            if a.category == .stocks && a.valuation == .balance && usesPortfolio {
                a.valuation = .portfolio
            }
            store.update(a)
        } else {
            var a = draftAccount(icon: resolvedIcon)
            a.name = trimmedName
            a.cashGroup = category == .cash ? cashGroup : nil
            store.add(a)
            onCreate?(a)
        }
        dismiss()
    }
}
