import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(\.portfolio) private var store
    @Binding var tab: AppTab
    @State private var showingSettings = false
    @State private var mode: ValueMode = .live

    var body: some View {
        ScrollView {
            if let latest = store.latest {
                // 即時：最新紀錄 × 現在的報價，和最新紀錄比較；紀錄：最新紀錄，和前一筆比較
                let live = mode == .live
                let current = live ? (store.liveSnapshot ?? latest) : latest
                let comparison = live ? latest : store.snapshot(before: latest)
                VStack(spacing: 16) {
                    HeroCard(snapshot: current, record: latest, previous: comparison, mode: $mode)
                    if live { AttributionCard(tab: $tab) }
                    TrendCard(live: live ? store.liveSnapshot.map { ($0.date, store.netWorth($0)) } : nil)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)],
                              spacing: 16) {
                        AllocationCard(snapshot: current)
                        MoversCard(snapshot: current, previous: comparison, title: live ? "紀錄以來變動最大" : "本期變動最大", tab: $tab)
                        CurrencyCard(snapshot: current)
                        QuotesCard(snapshot: current, previous: comparison)
                    }
                }
                .padding()
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView {
                    Label("還沒有任何紀錄", systemImage: "tray")
                } description: {
                    Text("新增帳戶後，按「更新資產」記下第一筆數字。")
                } actions: {
                    Button("更新資產") { store.isUpdating = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color.groupedBackground)
        .navigationTitle("總覽")
        // 每分鐘檢查一次，超過 5 分鐘就重新取得即時報價；存了新紀錄（持股可能變了）也會立即更新
        .task(id: store.latest?.id) {
            // 切回總覽時，資料還新就不重抓；存了新紀錄或超過 5 分鐘才更新
            if store.isLiveStale || store.liveBaseID != store.latest?.id { await store.refreshLive() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if store.isLiveStale { await store.refreshLive() }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                PrivacyToolbarButton(store: store)
                UpdateToolbarButton(store: store)
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: { Label("設定", systemImage: "gearshape") }
            }
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .environment(\.portfolio, store)
                    .toolbar { Button("完成") { showingSettings = false } }
            }
            .presentationDetents([.medium])
        }
        #endif
    }
}

// MARK: - 淨資產

enum ValueMode: Hashable { case live, record }

private struct HeroCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let record: Snapshot
    let previous: Snapshot?
    @Binding var mode: ValueMode

    var body: some View {
        let net = store.netWorth(snapshot)
        let isLive = mode == .live
        Card {
            HStack(alignment: .center) {
                status(isLive: isLive)
                Spacer()
                Picker("顯示", selection: $mode) {
                    Text("即時").tag(ValueMode.live)
                    Text("\(record.date.formatted(.dateTime.month(.defaultDigits).day())) 紀錄").tag(ValueMode.record)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 8) {
                MoneyText(value: net)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let previous {
                    let old = store.netWorth(previous)
                    HStack(spacing: 8) {
                        DeltaBadge(delta: net - old, base: old)
                        Text(isLive ? "自 \(previous.date.formatted(.dateTime.month(.defaultDigits).day())) 紀錄以來"
                                    : "較 \(previous.date.formatted(.dateTime.month(.defaultDigits).day()))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack { recordInfo; Spacer(); buttons(isLive: isLive) }
                VStack(alignment: .leading, spacing: 12) { recordInfo; HStack { buttons(isLive: isLive) } }
            }
        }
    }

    @ViewBuilder private func status(isLive: Bool) -> some View {
        Group {
            if !isLive {
                Label("紀錄的淨資產", systemImage: "tray.full")
            } else {
                switch store.liveStatus {
                case .loading where store.liveUpdatedAt == nil:
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("取得即時報價中…") }
                case .failed where store.liveUpdatedAt == nil:
                    Label("無法取得即時報價，顯示紀錄數字", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                default:
                    Label {
                        Text("即時淨資產 · \((store.liveUpdatedAt ?? .now).formatted(date: .omitted, time: .shortened)) 更新")
                    } icon: {
                        Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(.green)
                    }
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private var recordInfo: some View {
        Label {
            Text("最後紀錄 \(record.date.formatted(.dateTime.month(.defaultDigits).day()))")
            + Text(staleText).foregroundStyle(isStale ? .orange : .secondary)
        } icon: {
            Image(systemName: isStale ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isStale ? .orange : .green)
        }
        .font(.subheadline)
    }

    @ViewBuilder private func buttons(isLive: Bool) -> some View {
        if isLive {
            Button {
                Task { await store.refreshLive() }
            } label: {
                Label("重新整理", systemImage: "arrow.clockwise")
            }
            .disabled(store.liveStatus == .loading)
            .controlSize(.large)
        }
        Button {
            store.isUpdating = true
        } label: {
            Label(isLive ? "存成今天的紀錄" : "更新資產", systemImage: "square.and.pencil")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .help(isLive ? "打開更新畫面，報價與股價會自動帶入，只要確認餘額" : "輸入最新的餘額與報價")
    }

    private var days: Int { store.daysSinceLastUpdate ?? 0 }
    private var isStale: Bool { days >= 7 }
    private var staleText: String { days == 0 ? " · 今天" : " · \(days) 天前" }
}

// MARK: - 變化來源

private struct AttributionCard: View {
    @Environment(\.portfolio) private var store
    @Binding var tab: AppTab

    var body: some View {
        Card(title: "變化來源", systemImage: "chart.bar.xaxis") {
            if let a = store.liveAttribution {
                let hasHoldings = !store.heldSymbols.isEmpty
                let rows: [(String, String, Double, Color, Bool)] = [
                    ("股價", "chart.line.uptrend.xyaxis", a.stocks, AssetCategory.stocks.tint, hasHoldings),
                    ("幣價", "bitcoinsign.circle", a.crypto, AssetCategory.crypto.tint, true),
                    ("匯率", "dollarsign.arrow.circlepath", a.fx, .teal, true),
                ]
                let maxAbs = max(rows.map { abs($0.2) }.max() ?? 1, 1)
                VStack(spacing: 10) {
                    ForEach(rows, id: \.0) { title, icon, value, color, available in
                        HStack(spacing: 12) {
                            Label(title, systemImage: icon)
                                .frame(width: 76, alignment: .leading)
                            if available {
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(color.gradient)
                                        .frame(width: max(geo.size.width * abs(value) / maxAbs, 3), height: 8)
                                        .frame(maxHeight: .infinity, alignment: .center)
                                }
                                .frame(height: 12)
                                DeltaText(delta: value)
                                    .frame(minWidth: 110, alignment: .trailing)
                            } else {
                                Text("尚未設定持股").foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                        .font(.subheadline)
                    }
                    HStack(spacing: 12) {
                        Label("未連動", systemImage: "pause.circle")
                            .frame(width: 76, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(unlinkedText).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                    }
                    .font(.subheadline)
                }

                let unsetStocks = store.activeAccounts(in: .stocks).filter { !$0.isPortfolio }
                if !unsetStocks.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb").foregroundStyle(.yellow)
                        Text("\(unsetStocks.map(\.name).joined(separator: "、")) 記的是總金額，股價變動不會反映。到「帳戶」編輯並改成「持股明細」，填入股數即可。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("前往帳戶") { tab = .accounts(.all) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                    .padding(10)
                    .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                if !store.liveErrors.isEmpty {
                    Label(store.liveErrors.joined(separator: "；"), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else if store.liveStatus == .loading {
                HStack { ProgressView().controlSize(.small); Text("計算中…").foregroundStyle(.secondary) }
            } else {
                Text("目前無法取得即時報價，請稍後按「重新整理」。").foregroundStyle(.secondary)
            }
        }
    }

    private var unlinkedText: String {
        let names = store.activeAccounts.filter { !store.isMarketLinked($0) }.map(\.name)
        guard !names.isEmpty else { return "無" }
        let shown = names.prefix(3).joined(separator: "、")
        return names.count > 3 ? "\(shown) 等 \(names.count) 個帳戶維持紀錄數字" : "\(shown) 維持紀錄數字"
    }
}

// MARK: - 趨勢

private struct TrendCard: View {
    @Environment(\.portfolio) private var store
    /// 即時估值（日期、淨值），以虛線接在最後一筆紀錄後面
    var live: (Date, Double)?
    @State private var mode: Mode = .netWorth
    @State private var selectedDate: Date?

    enum Mode: String, CaseIterable, Identifiable {
        case netWorth = "淨值", byCategory = "分類"
        var id: Self { self }
    }

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        var category: AssetCategory? = nil
    }

    var body: some View {
        Card {
            HStack {
                Text("趨勢").font(.headline)
                Spacer()
                Picker("顯示", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            Group {
                switch mode {
                case .netWorth: netWorthChart
                case .byCategory: categoryChart
                }
            }
            .frame(height: 220)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(store.hideAmounts ? "" : Fmt.wan(v))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: store.snapshots.map(\.date)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), anchor: .top)
                }
            }
        }
    }

    private var netPoints: [Point] {
        store.snapshots.map { Point(date: $0.date, value: store.netWorth($0)) }
    }

    private var netWorthChart: some View {
        let points = netPoints
        let values = points.map(\.value) + (live.map { [$0.1] } ?? [])
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.25, hi * 0.01)
        let floor = lo - pad
        let selected = selectedDate.flatMap { d in points.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } }

        return Chart {
            ForEach(points) { p in
                AreaMark(x: .value("日期", p.date),
                         yStart: .value("下限", floor),
                         yEnd: .value("淨值", p.value))
                    .foregroundStyle(LinearGradient(colors: [.accentColor.opacity(0.25), .accentColor.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("日期", p.date), y: .value("淨值", p.value), series: .value("系列", "紀錄"))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("日期", p.date), y: .value("淨值", p.value))
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(selected?.date == p.date ? 120 : 30)
            }
            if let live, let last = points.last {
                ForEach([(last.date, last.value), live], id: \.0) { d, v in
                    LineMark(x: .value("日期", d), y: .value("淨值", v), series: .value("系列", "即時"))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                }
                PointMark(x: .value("日期", live.0), y: .value("淨值", live.1))
                    .foregroundStyle(Color.accentColor)
                    .symbol { Circle().strokeBorder(Color.accentColor, lineWidth: 2).background(Circle().fill(Color.cardBackground)).frame(width: 10, height: 10) }
                    .annotation(position: .top) {
                        Text("即時").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if let selected {
                RuleMark(x: .value("日期", selected.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(selected.date.formatted(.dateTime.month(.defaultDigits).day()))
                                .font(.caption).foregroundStyle(.secondary)
                            MoneyText(value: selected.value).font(.callout.bold())
                        }
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
        .chartYScale(domain: floor...(hi + pad))
        .chartXScale(range: .plotDimension(padding: 24))
        .chartXSelection(value: $selectedDate)
    }

    private var categoryChart: some View {
        let points = store.snapshots.flatMap { s in
            store.activeCategories.map { Point(date: s.date, value: store.total($0, in: s), category: $0) }
        }
        return Chart(points) { p in
            BarMark(x: .value("日期", p.date, unit: .day), y: .value("金額", p.value), width: .ratio(0.5))
                .foregroundStyle(by: .value("分類", p.category?.title ?? ""))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(domain: store.activeCategories.map(\.title),
                                   range: store.activeCategories.map(\.tint))
        .chartLegend(position: .bottom, alignment: .leading)
    }
}

// MARK: - 資產配置

private struct AllocationCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot

    var body: some View {
        let gross = store.grossAssets(snapshot)
        let slices = store.activeCategories.filter { !$0.isLiability }
            .map { ($0, store.total($0, in: snapshot)) }
        let debt = store.total(.liability, in: snapshot)

        Card(title: "資產配置", systemImage: "chart.pie") {
            // 寬度夠時圓環與圖例並排，iPhone 上改為上下排列
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) { donut(slices, gross: gross); legend(slices, gross: gross, debt: debt).frame(minWidth: 220) }
                VStack(spacing: 16) { donut(slices, gross: gross); legend(slices, gross: gross, debt: debt) }
            }
        }
    }

    private func donut(_ slices: [(AssetCategory, Double)], gross: Double) -> some View {
                Chart(slices, id: \.0) { cat, value in
                    SectorMark(angle: .value("金額", max(value, 0)),
                               innerRadius: .ratio(0.64), angularInset: 2)
                        .foregroundStyle(cat.tint.gradient)
                        .cornerRadius(4)
                }
                .frame(width: 130, height: 130)
                .chartBackground { _ in
                    VStack(spacing: 0) {
                        Text("總資產").font(.caption2).foregroundStyle(.secondary)
                        Text(store.hideAmounts ? "••••" : Fmt.wan(gross))
                            .font(.headline.monospacedDigit())
                    }
                }
    }

    private func legend(_ slices: [(AssetCategory, Double)], gross: Double, debt: Double) -> some View {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(slices, id: \.0) { cat, value in
                        HStack(spacing: 8) {
                            Circle().fill(cat.tint).frame(width: 8, height: 8)
                            Text(cat.title).font(.subheadline)
                            Spacer(minLength: 8)
                            Text((value / gross).formatted(.percent.precision(.fractionLength(0))))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                    }
                    if debt != 0 {
                        Divider()
                        HStack(spacing: 8) {
                            Circle().fill(AssetCategory.liability.tint).frame(width: 8, height: 8)
                            Text("負債").font(.subheadline)
                            Spacer(minLength: 8)
                            MoneyText(value: debt).font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .lineLimit(1)
    }
}

// MARK: - 本期變動

private struct MoversCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let previous: Snapshot?
    let title: String
    @Binding var tab: AppTab

    var body: some View {
        Card(title: title, systemImage: "arrow.up.arrow.down") {
            if let prev = previous {
                let movers = store.accounts
                    .map { ($0, store.value(of: $0, in: snapshot) - store.value(of: $0, in: prev), store.value(of: $0, in: prev)) }
                    .filter { abs($0.1) >= 1 }
                    .sorted { abs($0.1) > abs($1.1) }
                    .prefix(5)
                VStack(spacing: 10) {
                    ForEach(Array(movers), id: \.0.id) { account, delta, base in
                        HStack(spacing: 10) {
                            AccountAvatar(account: account, size: 28)
                            Text(account.name).font(.subheadline)
                            Spacer()
                            DeltaText(delta: delta, base: base)
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
                Button("查看所有帳戶") { tab = .accounts(.all) }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            } else {
                Text("再更新一次就能看到變動。")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 幣別曝險

private struct CurrencyCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot

    var body: some View {
        let parts = Currency.allCases.map { ($0, store.total($0, in: snapshot)) }.filter { $0.1 > 0 }
        let sum = parts.reduce(0) { $0 + $1.1 }

        Card(title: "幣別分布", systemImage: "globe.asia.australia") {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { c, v in
                        Rectangle().fill(c.tint.gradient)
                            .frame(width: max(geo.size.width * v / sum - 2, 2))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)

            VStack(spacing: 8) {
                ForEach(parts, id: \.0) { c, v in
                    HStack {
                        Circle().fill(c.tint).frame(width: 8, height: 8)
                        Text(c.name).font(.subheadline)
                        Spacer()
                        MoneyText(value: v).font(.subheadline).foregroundStyle(.secondary)
                        Text((v / sum).formatted(.percent.precision(.fractionLength(0))))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - 報價

private struct QuotesCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let previous: Snapshot?

    var body: some View {
        let prev = previous
        Card(title: "報價", systemImage: "chart.xyaxis.line") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                ForEach(Quote.allCases) { q in
                    let v = snapshot.quotes[q] ?? 0
                    GridRow {
                        Label(q.title, systemImage: q.symbol).font(.subheadline)
                        Text(Fmt.number(v))
                            .font(.subheadline.monospacedDigit())
                            .gridColumnAlignment(.trailing)
                        if let p = prev?.quotes[q], p != 0 {
                            Text(Fmt.percent((v - p) / p))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(store.deltaColor(v - p))
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }
}
