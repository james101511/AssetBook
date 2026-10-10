import SwiftUI
import Charts

/// 總覽：淨資產與走勢 → 資產組成 → 變動最大、市場
struct DashboardView: View {
    @Environment(\.portfolio) private var store
    @Binding var tab: AppTab
    @State private var mode: ValueMode = .live

    var body: some View {
        ScrollView {
            if let latest = store.latest {
                // 即時：最新紀錄 × 現在的報價，和最新紀錄比較；紀錄：最新紀錄，和前一筆比較
                let live = mode == .live
                let current = live ? (store.liveSnapshot ?? latest) : latest
                let comparison = live ? latest : store.snapshot(before: latest)
                VStack(spacing: 16) {
                    NetWorthCard(snapshot: current, record: latest, comparison: comparison, mode: $mode)
                    CompositionCard(snapshot: current, previous: comparison, tab: $tab)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 16, alignment: .top)],
                              spacing: 16) {
                        MoversCard(snapshot: current, previous: comparison,
                                   title: live ? "紀錄以來變動最大" : "本期變動最大", tab: $tab)
                        MarketCard(snapshot: current, previous: comparison)
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
        // 切回總覽時，資料還新就不重抓；存了新紀錄或超過 5 分鐘才更新
        .task(id: store.latest?.id) {
            if store.isLiveStale || store.liveBaseID != store.latest?.id { await store.refreshLive() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if store.isLiveStale { await store.refreshLive() }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if mode == .live {
                    Button {
                        Task { await store.refreshLive() }
                    } label: {
                        Label("重新整理", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.liveStatus == .loading)
                    .help("重新取得即時報價與股價")
                }
                PrivacyToolbarButton(store: store)
                UpdateToolbarButton(store: store)
            }
        }
    }
}

enum ValueMode: Hashable { case live, record }

// MARK: - 淨資產＋走勢

/// 數字和走勢圖是一體的：拖過圖表時，上方的大數字即時變成那一天的淨值
private struct NetWorthCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let record: Snapshot
    let comparison: Snapshot?
    @Binding var mode: ValueMode

    @State private var range: TimeRange = .all
    @State private var selectedDate: Date?

    enum TimeRange: String, CaseIterable, Identifiable {
        case month = "1個月", quarter = "3個月", year = "1年", all = "全部"
        var id: Self { self }
        var days: Int? {
            switch self {
            case .month: 31
            case .quarter: 92
            case .year: 366
            case .all: nil
            }
        }
    }

    private struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
        var isLive = false
    }

    var body: some View {
        let pts = points
        let selected = selectedDate.flatMap { d in pts.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) } }
        let net = store.netWorth(snapshot)
        let color = trendColor(pts)

        Card {
            HStack(alignment: .center) {
                status
                Spacer()
                Picker("顯示", selection: $mode) {
                    Text("即時").tag(ValueMode.live)
                    Text("\(record.date.formatted(.dateTime.month(.defaultDigits).day())) 紀錄").tag(ValueMode.record)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 6) {
                MoneyText(value: selected?.value ?? net)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let selected, let first = pts.first {
                        // 拖曳中：和區間起點比較
                        DeltaBadge(delta: selected.value - first.value, base: first.value)
                        Text(selected.isLive ? "即時 · 較區間起點" : "\(selected.date.formatted(.dateTime.year().month(.defaultDigits).day())) · 較區間起點")
                            .foregroundStyle(.secondary)
                    } else if let comparison {
                        let old = store.netWorth(comparison)
                        DeltaBadge(delta: net - old, base: old)
                        Text(mode == .live ? "自 \(comparison.date.formatted(.dateTime.month(.defaultDigits).day())) 紀錄以來"
                                           : "較 \(comparison.date.formatted(.dateTime.month(.defaultDigits).day()))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    staleReminder
                }
                .font(.subheadline)
            }

            chart(pts, selected: selected, color: color)
                .frame(height: 230)
                .padding(.top, 4)

            HStack(spacing: 4) {
                ForEach(TimeRange.allCases) { r in
                    Button {
                        withAnimation(.snappy) { range = r }
                    } label: {
                        Text(r.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(range == r ? Color.primary.opacity(0.08) : .clear, in: Capsule())
                            .foregroundStyle(range == r ? .primary : .secondary)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: 狀態

    @ViewBuilder private var status: some View {
        Group {
            if mode == .record {
                Label("淨資產 · 紀錄", systemImage: "tray.full")
            } else {
                switch store.liveStatus {
                case .loading where store.liveUpdatedAt == nil:
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("取得即時報價中…") }
                case .failed where store.liveUpdatedAt == nil:
                    Label("無法取得即時報價，顯示紀錄數字", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                default:
                    Label {
                        Text("淨資產 · 即時 \((store.liveUpdatedAt ?? .now).formatted(date: .omitted, time: .shortened))")
                    } icon: {
                        Circle().fill(.green).frame(width: 7, height: 7)
                    }
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
    }

    /// 超過 7 天沒記錄才出現
    @ViewBuilder private var staleReminder: some View {
        let days = store.daysSinceLastUpdate ?? 0
        if days >= 7 {
            Button {
                store.isUpdating = true
            } label: {
                Label("\(days) 天沒記錄了", systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("打開更新畫面，報價與股價會自動帶入")
        }
    }

    // MARK: 走勢圖

    /// 範圍內的紀錄；起點前一筆也帶進來，線才不會從中間開始
    private var points: [Point] {
        let all = store.snapshots
        var inRange = all
        if let days = range.days, let end = all.last?.date,
           let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: end) {
            inRange = all.filter { $0.date >= cutoff }
            if let before = all.last(where: { $0.date < cutoff }) { inRange.insert(before, at: 0) }
        }
        var p = inRange.map { Point(date: $0.date, value: store.netWorth($0)) }
        if mode == .live, let live = store.liveSnapshot {
            p.append(Point(date: live.date, value: store.netWorth(live), isLive: true))
        }
        return p
    }

    /// 依區間漲跌決定線的顏色（跟隨紅漲綠跌設定）
    private func trendColor(_ pts: [Point]) -> Color {
        guard let a = pts.first?.value, let b = pts.last?.value, abs(b - a) >= 1 else { return .accentColor }
        return store.deltaColor(b - a)
    }

    private func chart(_ pts: [Point], selected: Point?, color: Color) -> some View {
        let recorded = pts.filter { !$0.isLive }
        let values = pts.map(\.value)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.2, hi * 0.005)
        let floor = lo - pad
        let last = pts.last

        return Chart {
            ForEach(recorded) { p in
                AreaMark(x: .value("日期", p.date), yStart: .value("下限", floor), yEnd: .value("淨值", p.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("日期", p.date), y: .value("淨值", p.value), series: .value("系列", "紀錄"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
            }
            if let livePoint = pts.last, livePoint.isLive, let lastRecord = recorded.last {
                ForEach([lastRecord, livePoint]) { p in
                    LineMark(x: .value("日期", p.date), y: .value("淨值", p.value), series: .value("系列", "即時"))
                        .foregroundStyle(color.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5]))
                }
            }
            if let last, selected == nil {
                PointMark(x: .value("日期", last.date), y: .value("淨值", last.value))
                    .symbolSize(340)
                    .foregroundStyle(color.opacity(0.18))
                PointMark(x: .value("日期", last.date), y: .value("淨值", last.value))
                    .symbolSize(64)
                    .foregroundStyle(color)
            }
            if let selected {
                RuleMark(x: .value("日期", selected.date))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                PointMark(x: .value("日期", selected.date), y: .value("淨值", selected.value))
                    .symbolSize(100)
                    .foregroundStyle(color)
            }
        }
        .chartYScale(domain: floor...(hi + pad))
        .chartXScale(range: .plotDimension(padding: 12))
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(store.hideAmounts ? "" : Fmt.wan(v)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            }
        }
        .animation(.snappy, value: range)
    }
}

// MARK: - 資產組成

/// 像 iPhone「儲存空間」那樣的分段條，下面每個分類（或幣別）一張小卡
private struct CompositionCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let previous: Snapshot?
    @Binding var tab: AppTab

    @State private var grouping: Grouping = .category
    @State private var hovered: String?

    enum Grouping: String, CaseIterable, Identifiable {
        case category = "分類", currency = "幣別"
        var id: Self { self }
    }

    private struct Part: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let color: Color
        let value: Double
        let previous: Double?
        let category: AssetCategory?
    }

    private var parts: [Part] {
        switch grouping {
        case .category:
            return AssetCategory.allCases.filter { !$0.isLiability && !store.activeAccounts(in: $0).isEmpty }.map { c in
                Part(id: c.rawValue, title: c.title, symbol: c.symbol, color: c.tint,
                     value: max(store.total(c, in: snapshot), 0),
                     previous: previous.map { store.total(c, in: $0) }, category: c)
            }
        case .currency:
            return Currency.allCases.map { c in
                Part(id: c.rawValue, title: c.name, symbol: currencySymbol(c), color: c.tint,
                     value: max(store.total(c, in: snapshot), 0),
                     previous: previous.map { store.total(c, in: $0) }, category: nil)
            }
            .filter { $0.value > 0 }
        }
    }

    private func currencySymbol(_ c: Currency) -> String {
        switch c {
        case .twd: "dollarsign.circle.fill"
        case .usd: "dollarsign.square.fill"
        case .jpy: "yensign.circle.fill"
        }
    }

    var body: some View {
        let parts = parts
        let gross = store.grossAssets(snapshot)
        let debt = -store.total(.liability, in: snapshot)

        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("資產組成").font(.headline)
                    HStack(spacing: 4) {
                        Text("總資產")
                        MoneyText(value: gross)
                        if debt > 0 {
                            Text("· 負債")
                            MoneyText(value: debt)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("分組", selection: $grouping.animation(.snappy)) {
                    ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            // 分段條
            GeometryReader { geo in
                let gap: CGFloat = 3
                let usable = geo.size.width - gap * CGFloat(max(parts.count - 1, 0))
                HStack(spacing: gap) {
                    ForEach(parts) { p in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(p.color.gradient)
                            .frame(width: max(usable * p.value / max(gross, 1), 6))
                            .opacity(hovered == nil || hovered == p.id ? 1 : 0.35)
                    }
                }
            }
            .frame(height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.snappy, value: grouping)

            // 寬螢幕：每個分類一張小卡並排撐滿；窄螢幕：精簡列表
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    ForEach(parts) { p in
                        tile(p, gross: gross).frame(minWidth: 170)
                    }
                }
                VStack(spacing: 6) {
                    ForEach(parts) { p in
                        tile(p, gross: gross, compact: true)
                    }
                }
            }
        }
    }

    private func tile(_ p: Part, gross: Double, compact: Bool = false) -> some View {
        let share = gross > 0 ? p.value / gross : 0
        let full = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: p.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(p.color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(p.title).font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
                if p.category != nil {
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            MoneyText(value: p.value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .fontWeight(.semibold)
                    .foregroundStyle(p.color)
                if let old = p.previous {
                    DeltaText(delta: p.value - old, base: old, showPercentOnly: true)
                }
            }
            .font(.caption)
        }
        // 窄螢幕的一列：圖示、名稱、佔比｜金額、漲跌
        let row = HStack(spacing: 10) {
            Image(systemName: p.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(p.color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(p.title).font(.subheadline.weight(.medium))
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.weight(.semibold)).foregroundStyle(p.color)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                MoneyText(value: p.value).font(.subheadline.weight(.semibold))
                if let old = p.previous {
                    DeltaText(delta: p.value - old, base: old, showPercentOnly: true).font(.caption)
                }
            }
            if p.category != nil {
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }

        let content = Group {
            if compact { row } else { full }
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.color.opacity(hovered == p.id ? 0.14 : 0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { inside in withAnimation(.snappy(duration: 0.2)) { hovered = inside ? p.id : nil } }

        return Group {
            if let category = p.category {
                Button { tab = .accounts(AccountsFilter(category)) } label: { content }
                    .buttonStyle(.plain)
                    .help("查看\(category.title)的帳戶")
            } else {
                content
            }
        }
    }
}

// MARK: - 變動最大

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
                if movers.isEmpty {
                    Text("目前沒有變動。").foregroundStyle(.secondary)
                }
                VStack(spacing: 12) {
                    ForEach(Array(movers), id: \.0.id) { account, delta, base in
                        HStack(spacing: 10) {
                            AccountAvatar(account: account, size: 28)
                            Text(account.name).font(.subheadline).lineLimit(1)
                            Spacer(minLength: 8)
                            // 顏色跟著線本身的走勢（第一筆到最後一筆），和線的形狀一致
                            let series = history(of: account)
                            Sparkline(values: series, color: store.deltaColor((series.last ?? 0) - (series.first ?? 0)))
                                .frame(width: 60, height: 22)
                            DeltaText(delta: delta, base: base)
                                .font(.subheadline.weight(.medium))
                                .frame(minWidth: 96, alignment: .trailing)
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

    /// 各筆紀錄的台幣價值，最後加上目前顯示的快照（即時模式時為即時估值）
    private func history(of account: Account) -> [Double] {
        var values = store.snapshots.filter { $0.id != snapshot.id }.map { store.value(of: account, in: $0) }
        values.append(store.value(of: account, in: snapshot))
        return values
    }
}

// MARK: - 市場

/// 匯率與幣價：每個報價一張小卡，附迷你走勢
private struct MarketCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let previous: Snapshot?

    var body: some View {
        Card(title: "市場", systemImage: "chart.xyaxis.line") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Quote.allCases) { q in
                    tile(q)
                }
            }
        }
    }

    private func tile(_ q: Quote) -> some View {
        let value = snapshot.quotes[q] ?? 0
        let old = previous?.quotes[q]
        var series = store.snapshots.filter { $0.id != snapshot.id }.compactMap { $0.quotes[q] }
        series.append(value)
        let change = old.map { value - $0 } ?? 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: q.symbol).foregroundStyle(.secondary)
                Text(q.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.number(value, digits: 0...(value < 1 ? 5 : value < 100 ? 3 : 0)))
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let old, old != 0 {
                        Text(Fmt.percent(change / old))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(store.deltaColor(change))
                    }
                }
                Spacer(minLength: 4)
                Sparkline(values: series, color: store.deltaColor((series.last ?? 0) - (series.first ?? 0)))
                    .frame(width: 52, height: 26)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 迷你走勢線

private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.3, abs(hi) * 0.0001)
        Chart(Array(values.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("i", i), yStart: .value("min", lo - pad), yEnd: .value("v", v))
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("i", i), y: .value("v", v))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXScale(range: .plotDimension(padding: 2))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}
