import SwiftUI
import Charts

/// 總覽：淨資產與走勢 → 重點數字（總資產、負債、近期變動）→ 資產組成 → 市場
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
                    StatStrip(snapshot: current)
                    CompositionCard(snapshot: current, previous: comparison, tab: $tab)
                    MarketCard(snapshot: current, previous: comparison)
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
        case week = "7天", month = "1個月", quarter = "3個月", year = "1年", all = "全部"
        var id: Self { self }
        var days: Int? {
            switch self {
            case .week: 7
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
        /// 自動記錄的估值點（不是手動記錄）
        var isAuto = false
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
                    .font(.system(size: 48, weight: .regular))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let selected, let first = pts.first {
                        // 拖曳中：和區間起點比較
                        DeltaBadge(delta: selected.value - first.value, base: first.value)
                        Text(selected.isLive ? "即時 vs 區間起點" : "\(selected.date.formatted(.dateTime.year().month(.defaultDigits).day())) vs 區間起點")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else if let comparison {
                        let old = store.netWorth(comparison)
                        DeltaBadge(delta: net - old, base: old)
                        Text("vs \(comparison.date.formatted(.dateTime.month(.defaultDigits).day()))\(mode == .live ? " 紀錄" : "")")
                            .monospacedDigit()
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

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(TimeRange.allCases) { r in
                        let redundant = isRedundant(r)
                        Button {
                            withAnimation(.snappy) { range = r }
                        } label: {
                            Text(r.rawValue)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(range == r ? Color.primary.opacity(0.07) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .foregroundStyle(range == r ? AnyShapeStyle(.primary)
                                                 : redundant ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.secondary))
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(redundant)
                        .help(redundant ? "紀錄還不到\(r.rawValue)，內容和「全部」相同" : "")
                    }
                }
                // 這個區間的漲跌：切換範圍時數字會跟著變
                if let first = pts.first, let last = pts.last, first.date != last.date {
                    HStack(spacing: 6) {
                        DeltaText(delta: last.value - first.value)
                        if first.value != 0 {
                            Text("(\(Fmt.percent((last.value - first.value) / abs(first.value))))")
                                .foregroundStyle(store.deltaColor(last.value - first.value))
                        }
                        Text("vs \(first.date.formatted(.dateTime.month(.defaultDigits).day()))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 紀錄的時間跨度（天）
    private var historyDays: Int {
        let all = store.chartSnapshots
        guard let first = all.first?.date, let last = all.last?.date else { return 0 }
        return Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
    }

    /// 比紀錄還長、而且已經有較短的選項能涵蓋全部紀錄時，這個選項和「全部」完全一樣
    private func isRedundant(_ r: TimeRange) -> Bool {
        guard let days = r.days else { return false }
        let covering = TimeRange.allCases.compactMap(\.days).first { $0 >= historyDays }
        return covering.map { days > $0 } ?? false
    }

    // MARK: 狀態

    @ViewBuilder private var status: some View {
        Group {
            if mode == .record {
                Label("淨資產 · 紀錄", systemImage: "tray.full")
            } else {
                switch store.liveStatus {
                case .loading where store.liveUpdatedAt == nil:
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("取得即時報價中") }
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
                Label("\(days) 天沒記錄", systemImage: "clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("打開更新畫面，報價與股價會自動帶入")
        }
    }

    // MARK: 走勢圖

    /// 範圍內的紀錄；起點前一筆也帶進來，線才不會從中間開始
    private var points: [Point] {
        let all = store.chartSnapshots
        var inRange = all
        if let days = range.days, let end = all.last?.date,
           let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: end) {
            inRange = all.filter { $0.date >= cutoff }
            if let before = all.last(where: { $0.date < cutoff }) { inRange.insert(before, at: 0) }
        }
        var p = inRange.map { Point(date: $0.date, value: store.netWorth($0), isAuto: store.isAuto($0)) }
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
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.14), color.opacity(0.0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("日期", p.date), y: .value("淨值", p.value), series: .value("系列", "紀錄"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                // 每個記錄日一個點：手動記錄是實心，自動估值點是小的淡點
                PointMark(x: .value("日期", p.date), y: .value("淨值", p.value))
                    .symbolSize(p.isAuto ? 14 : 32)
                    .foregroundStyle(p.isAuto ? color.opacity(0.45) : color)
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
                    .symbolSize(44)
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
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(store.hideAmounts ? "" : Fmt.wan(v)) }
                }
                .font(.caption2)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
        }
        .animation(.snappy, value: range)
    }
}

// MARK: - 一眼看完的數字

private struct StatStrip: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot

    var body: some View {
        let gross = store.grossAssets(snapshot)
        let debt = -store.total(.liability, in: snapshot)
        let net = store.netWorth(snapshot)
        // 約 30 天前的紀錄（沒有那麼久就用最早一筆）
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: snapshot.date) ?? snapshot.date
        let base = store.snapshots.last { $0.date <= cutoff } ?? store.snapshots.first

        let assets = tile("總資產") {
            MoneyText(value: gross)
        } footer: {
            Text("\(store.activeAccounts.filter { !$0.category.isLiability }.count) 個帳戶")
        }
        let liabilities = tile("負債") {
            MoneyText(value: debt)
        } footer: {
            Text(gross > 0 ? "佔總資產 \((debt / gross).formatted(.percent.precision(.fractionLength(1))))" : "—")
        }
        let change = tile(base.map { "自 \($0.date.formatted(.dateTime.month(.defaultDigits).day())) 以來" } ?? "近 30 天") {
                if let base, base.id != snapshot.id {
                    DeltaText(delta: net - store.netWorth(base))
                } else {
                    Text("—")
                }
            } footer: {
                if let base, base.id != snapshot.id {
                    let old = store.netWorth(base)
                    Text(old != 0 ? "\(Fmt.percent((net - old) / abs(old))) vs \(base.date.formatted(.dateTime.month(.defaultDigits).day()))" : "")
                }
            }

        // 寬螢幕：三張等寬一排；窄螢幕：總資產與負債並排，近期變動撐滿一排
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                assets.frame(minWidth: 200)
                liabilities.frame(minWidth: 200)
                change.frame(minWidth: 200)
            }
            VStack(spacing: 12) {
                HStack(spacing: 12) { assets; liabilities }
                change
            }
        }
    }

    /// 數字卡只放：標題、數字、說明，不加圖示
    private func tile<V: View, F: View>(_ title: String,
                                         @ViewBuilder value: () -> V, @ViewBuilder footer: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            value()
                .font(.system(size: 24, weight: .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 28, alignment: .leading)
            footer()
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - 資產組成

/// 動畫圓環圖＋圖例。滑過或點選某一塊，那一塊會變粗、其他變淡，中間顯示它的金額與佔比。
private struct CompositionCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let previous: Snapshot?
    @Binding var tab: AppTab

    @State private var grouping: Grouping = .category
    @State private var selected: String?
    @State private var appeared = false

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
        let count: Int
        let category: AssetCategory?
    }

    private var parts: [Part] {
        switch grouping {
        case .category:
            return AssetCategory.allCases.filter { !$0.isLiability && !store.activeAccounts(in: $0).isEmpty }.map { c in
                Part(id: c.rawValue, title: c.title, symbol: c.symbol, color: c.tint,
                     value: max(store.total(c, in: snapshot), 0),
                     previous: previous.map { store.total(c, in: $0) },
                     count: store.activeAccounts(in: c).count, category: c)
            }
        case .currency:
            return Currency.allCases.map { c in
                Part(id: c.rawValue, title: c.name, symbol: currencySymbol(c), color: c.tint,
                     value: max(store.total(c, in: snapshot), 0),
                     previous: previous.map { store.total(c, in: $0) },
                     count: store.activeAccounts.filter { $0.currency == c && !$0.category.isLiability }.count,
                     category: nil)
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
        let gross = max(parts.reduce(0) { $0 + $1.value }, 1)

        Card {
            HStack(alignment: .center) {
                Text("資產組成").font(.headline.weight(.medium))
                if let d = previous?.date {
                    Text("漲跌 vs \(d.formatted(.dateTime.month(.defaultDigits).day()))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer()
                Picker("分組", selection: $grouping) {
                    ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            // 寬螢幕：圓環在左、圖例在右；窄螢幕：上下排列
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 36) {
                    donut(parts, gross: gross).frame(width: 230, height: 230)
                    legend(parts, gross: gross).frame(minWidth: 340)
                }
                VStack(spacing: 22) {
                    donut(parts, gross: gross).frame(width: 210, height: 210)
                    legend(parts, gross: gross)
                }
            }
            .padding(.top, 4)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.1)) { appeared = true }
        }
        .onChange(of: grouping) { _, _ in
            // 切換分組時重新播放動畫
            selected = nil
            appeared = false
            withAnimation(.easeOut(duration: 0.7)) { appeared = true }
        }
    }

    private func donut(_ parts: [Part], gross: Double) -> some View {
        let current = parts.first { $0.id == selected }
        return DonutChart(slices: parts.map { .init(id: $0.id, color: $0.color, value: $0.value) },
                          selected: $selected, progress: appeared ? 1 : 0)
            .overlay {
                VStack(spacing: 3) {
                    if let current {
                        Text(current.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        CountingMoney(value: current.value, hidden: store.hideAmounts)
                            .font(.system(size: 22, weight: .regular))
                        Text((current.value / gross).formatted(.percent.precision(.fractionLength(1))))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("總資產")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        CountingMoney(value: appeared ? gross : 0, hidden: store.hideAmounts)
                            .font(.system(size: 22, weight: .regular))
                        Text("\(parts.count) 個\(grouping == .category ? "分類" : "幣別")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 46)
                .allowsHitTesting(false)
                .animation(.snappy(duration: 0.25), value: selected)
            }
    }

    private func legend(_ parts: [Part], gross: Double) -> some View {
        VStack(spacing: 4) {
            ForEach(parts) { p in
                legendRow(p, share: p.value / gross)
            }
        }
    }

    private func legendRow(_ p: Part, share: Double) -> some View {
        let isSelected = selected == p.id
        let row = VStack(spacing: 8) {
            HStack(spacing: 12) {
                // 分類只用一個小色點對應圓環的顏色
                Circle().fill(p.color).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).font(.subheadline.weight(.medium))
                    Text("\(p.count) 個帳戶").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    MoneyText(value: p.value).font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        if let old = p.previous {
                            DeltaText(delta: p.value - old, base: old, showPercentOnly: true)
                        }
                        Text(share.formatted(.percent.precision(.fractionLength(0))))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                }
                if p.category != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(p.color)
                        .frame(width: max(geo.size.width * share * (appeared ? 1 : 0), appeared ? 4 : 0))
                }
            }
            .frame(height: 4)
            .padding(.leading, 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(isSelected ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(selected == nil || isSelected ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.2)) { selected = inside ? p.id : (selected == p.id ? nil : selected) }
        }

        return Group {
            if let category = p.category {
                Button { tab = .accounts(AccountsFilter(category)) } label: { row }
                    .buttonStyle(.plain)
                    .help("查看\(category.title)的帳戶")
            } else {
                row
            }
        }
    }
}

/// 自己畫的圓環圖：每一段是一條圓弧，進場時順時針展開；被選取的那段會變粗，其他變淡
private struct DonutChart: View {
    struct Slice: Identifiable {
        let id: String
        let color: Color
        let value: Double
    }

    private struct Arc: Identifiable {
        let id: String
        let color: Color
        let start: CGFloat
        let end: CGFloat
    }

    let slices: [Slice]
    @Binding var selected: String?
    /// 0 → 1：進場動畫的進度
    var progress: CGFloat
    var lineWidth: CGFloat = 26

    private var arcs: [Arc] {
        let total = max(slices.reduce(0) { $0 + $1.value }, 1)
        var cursor: CGFloat = 0
        return slices.map { s in
            let span = CGFloat(s.value / total)
            defer { cursor += span }
            return Arc(id: s.id, color: s.color, start: cursor, end: cursor + span)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // 留空間給選取時變粗的線條和光暈
            let radius = (side - lineWidth - 18) / 2
            // 圓頭線帽會往兩端各多畫半個線寬，間隔要把它算進去
            let gap = (lineWidth + 5) / (2 * .pi * radius)
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.05), lineWidth: lineWidth)
                    .frame(width: radius * 2, height: radius * 2)
                ForEach(arcs) { arc in
                    segment(arc, gap: gap, radius: radius)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Circle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): select(hit(point, in: geo.size, radius: radius))
                case .ended: select(nil)
                }
            }
            .onTapGesture { point in
                let id = hit(point, in: geo.size, radius: radius)
                select(selected == id ? nil : id)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.easeOut(duration: 0.4), value: slices.map(\.value))
    }

    @ViewBuilder private func segment(_ arc: Arc, gap: CGFloat, radius: CGFloat) -> some View {
        let isSelected = selected == arc.id
        let span = arc.end - arc.start
        // 太小的一段放不下圓頭，改用平頭細線，至少看得到
        let tiny = span <= gap * 1.3
        let inset = tiny ? min(span * 0.15, 0.002) : gap / 2
        let from = (arc.start + inset) * progress
        let to = max((arc.end - inset) * progress, from)
        Circle()
            .trim(from: from, to: to)
            .stroke(arc.color,
                    style: StrokeStyle(lineWidth: isSelected ? lineWidth + 7 : lineWidth, lineCap: tiny ? .butt : .round))
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.degrees(-90))
            .opacity(selected == nil || isSelected ? 1 : 0.28)
    }

    private func select(_ id: String?) {
        guard id != selected else { return }
        withAnimation(.easeOut(duration: 0.2)) { selected = id }
    }

    /// 滑鼠或手指的位置落在哪一段（不在圓環上就回傳 nil）
    private func hit(_ point: CGPoint, in size: CGSize, radius: CGFloat) -> String? {
        let dx = point.x - size.width / 2, dy = point.y - size.height / 2
        let distance = sqrt(dx * dx + dy * dy)
        guard abs(distance - radius) <= lineWidth / 2 + 10 else { return nil }
        var fraction = atan2(dx, -dy) / (2 * .pi)   // 從 12 點鐘方向順時針
        if fraction < 0 { fraction += 1 }
        return arcs.first { fraction >= $0.start && fraction < $0.end }?.id
    }
}

/// 會跟著動畫逐格跳動的金額（圓環中間的數字）
private struct CountingMoney: View, Animatable {
    var value: Double
    var hidden: Bool

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(hidden ? "••••••" : Fmt.money(value, .twd))
            .monospacedDigit()
    }
}

// MARK: - 市場

/// 匯率、幣價與持股現價：每個報價一張小卡，只放數字與漲跌
private struct MarketCard: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot
    let previous: Snapshot?

    private struct Item: Identifiable {
        let id: String
        let title: String
        let badge: AnyView
        let value: Double
        let prefix: String
        var digits: ClosedRange<Int>? = nil
        let old: Double?
    }

    private var items: [Item] {
        var out = Quote.allCases.map { q -> Item in
            Item(id: q.id, title: q.title, badge: AnyView(Image(systemName: q.symbol)),
                 value: snapshot.quotes[q] ?? 0, prefix: "", old: previous?.quotes[q])
        }
        // 持股的現價（即時模式為即時股價，否則為該筆紀錄的股價）
        var seen = Set<String>()
        for p in snapshot.holdings.values.flatMap({ $0 }) where seen.insert(p.symbol).inserted {
            guard let price = snapshot.stockPrices[p.symbol] else { continue }
            let cur = store.liveStocks[p.symbol]?.currency ?? Self.guessCurrency(p.symbol)
            out.append(Item(id: p.symbol, title: p.name.isEmpty ? StockService.displaySymbol(p.symbol) : p.name,
                            badge: AnyView(Text(StockService.displaySymbol(p.symbol)).monospacedDigit()),
                            value: price, prefix: cur.symbol, digits: 0...(cur == .jpy ? 1 : 2),
                            old: previous?.stockPrices[p.symbol]))
        }
        return out
    }

    private static func guessCurrency(_ symbol: String) -> Currency {
        if symbol.hasSuffix(".TW") || symbol.hasSuffix(".TWO") { return .twd }
        if symbol.hasSuffix(".T") { return .jpy }
        return .usd
    }

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text("市場").font(.headline.weight(.medium))
                if let d = previous?.date {
                    Text("漲跌 vs \(d.formatted(.dateTime.month(.defaultDigits).day()))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            let items = items
            // 寬螢幕四張一排，窄螢幕兩張一排
            ViewThatFits(in: .horizontal) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(items) { tile($0) }
                }
                .frame(minWidth: 760)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(items) { tile($0) }
                }
            }
        }
    }

    private func tile(_ item: Item) -> some View {
        let change = item.old.map { item.value - $0 } ?? 0
        let value = item.value

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                item.badge.foregroundStyle(.secondary)
                Text(item.title).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption)
            HStack(alignment: .firstTextBaseline) {
                Text(item.prefix + Fmt.number(value, digits: item.digits ?? 0...(value < 1 ? 5 : value < 100 ? 3 : 0)))
                    .font(.system(size: 17, weight: .regular))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if let old = item.old, old != 0 {
                    let pct = change / old
                    // 四捨五入後是 0.0% 的就用灰色，不要紅綠
                    Text(Fmt.percent(pct))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(store.deltaColor(abs(pct) < 0.0005 ? 0 : change))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
