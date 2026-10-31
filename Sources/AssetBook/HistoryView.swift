import SwiftUI

struct HistoryView: View {
    @Environment(\.portfolio) private var store
    @State private var pendingDelete: Snapshot?
    @State private var mode: Mode = .calendar
    /// 目前顯示的月份（該月 1 號）
    @State private var month: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    enum Mode: String, CaseIterable, Identifiable {
        case calendar = "日曆", list = "列表"
        var id: Self { self }
    }

    var body: some View {
        Group {
            switch mode {
            case .calendar: calendarView
            case .list: listView
            }
        }
        .navigationTitle("歷史紀錄")
        .navigationDestination(for: Snapshot.self) { SnapshotDetailView(snapshot: $0) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("檢視", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Menu {
                    Button("複製為試算表", systemImage: "doc.on.clipboard") { store.copySheetToClipboard() }
                    Button("匯出 CSV 檔…", systemImage: "square.and.arrow.down") { store.isExportingSheet = true }
                } label: {
                    Label("匯出成試算表", systemImage: "tablecells")
                }
                .help("匯出所有紀錄，可貼到 Google 試算表")
                UpdateToolbarButton(store: store)
            }
        }
        .onAppear {
            // 第一次打開時，跳到最新紀錄所在的月份
            if let last = store.snapshots.last?.date,
               let start = Calendar.current.dateInterval(of: .month, for: last)?.start { month = start }
        }
        .confirmationDialog("刪除這筆紀錄？", isPresented: .init(get: { pendingDelete != nil },
                                                          set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { s in
            Button("刪除 \(s.date.formatted(.dateTime.month(.defaultDigits).day())) 的紀錄", role: .destructive) {
                withAnimation { store.delete(s) }
            }
        } message: { _ in
            Text("這個動作無法復原。")
        }
    }

    // MARK: 日曆

    private var calendarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    monthHeader
                    weekdayRow
                    dayGrid
                }
                monthSummary
            }
            .padding()
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
    }

    private var cal: Calendar { .current }

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.easeOut(duration: 0.2)) { month = d }
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Text(month.formatted(.dateTime.year().month(.wide)))
                .font(.title3.weight(.medium))
            Spacer()
            Button("今天") {
                if let start = cal.dateInterval(of: .month, for: .now)?.start {
                    withAnimation(.easeOut(duration: 0.2)) { month = start }
                }
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .help("上個月")
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .help("下個月")
        }
        .foregroundStyle(.primary)
    }

    private var weekdayRow: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                Text(symbols[(first + i) % 7])
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 這個月的每一格：前面補空白，讓 1 號對到正確的星期
    private var dayCells: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let lead = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for d in 0..<count { cells.append(cal.date(byAdding: .day, value: d, to: interval.start)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var dayGrid: some View {
        let byDay = Dictionary(store.snapshots.map { (cal.startOfDay(for: $0.date), $0) },
                               uniquingKeysWith: { a, _ in a })
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(Array(dayCells.enumerated()), id: \.offset) { _, day in
                if let day {
                    if let snap = byDay[cal.startOfDay(for: day)] {
                        NavigationLink(value: snap) {
                            DayCell(day: day, snapshot: snap, previous: store.snapshot(before: snap))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("刪除紀錄", systemImage: "trash", role: .destructive) { pendingDelete = snap }
                        }
                    } else {
                        DayCell(day: day, snapshot: nil, previous: nil)
                    }
                } else {
                    Color.clear.frame(height: 76)
                }
            }
        }
    }

    /// 這個月的紀錄數與淨資產變化（和上個月最後一筆比）
    @ViewBuilder private var monthSummary: some View {
        let inMonth = store.snapshots.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
        if let last = inMonth.last {
            let baseline = store.snapshots.last { $0.date < (inMonth.first?.date ?? last.date) } ?? inMonth.first!
            let delta = store.netWorth(last) - store.netWorth(baseline)
            HStack(spacing: 8) {
                Text("本月 \(inMonth.count) 筆紀錄")
                if baseline.id != last.id {
                    Text("·")
                    DeltaText(delta: delta)
                    Text("vs \(baseline.date.formatted(.dateTime.month(.defaultDigits).day()))")
                }
            }
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        } else {
            Text("這個月沒有紀錄")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: 列表

    private var listView: some View {
        List {
            ForEach(store.snapshots.reversed()) { s in
                NavigationLink(value: s) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.date.formatted(.dateTime.year().month().day()))
                                .font(.body.weight(.medium))
                            Text(s.date.formatted(.relative(presentation: .named)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            let net = store.netWorth(s)
                            MoneyText(value: net).font(.body.weight(.medium))
                            if let prev = store.snapshot(before: s) {
                                let old = store.netWorth(prev)
                                DeltaText(delta: net - old, base: old).font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .swipeActions {
                    Button("刪除", systemImage: "trash", role: .destructive) { pendingDelete = s }
                }
                .contextMenu {
                    Button("刪除紀錄", systemImage: "trash", role: .destructive) { pendingDelete = s }
                }
            }
        }
    }
}

/// 日曆裡的一天：有紀錄就顯示淨資產與變動，點下去看那天的明細
private struct DayCell: View {
    @Environment(\.portfolio) private var store
    let day: Date
    let snapshot: Snapshot?
    let previous: Snapshot?

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.caption.weight(isToday ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : (snapshot == nil ? Color.secondary : Color.primary))
                .frame(minWidth: 20, minHeight: 20)
                .background(isToday ? Color.accentColor : .clear, in: Circle())
            if let snapshot {
                let net = store.netWorth(snapshot)
                Spacer(minLength: 0)
                Text(store.hideAmounts ? "••" : Fmt.wan(net))
                    .font(.system(size: 12).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let previous {
                    let d = net - store.netWorth(previous)
                    Text(store.hideAmounts ? (d > 0 ? "▲" : d < 0 ? "▼" : "—")
                                           : (d > 0 ? "+" : "") + Fmt.wan(d))
                        .font(.system(size: 10)).monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(store.deltaColor(d))
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(snapshot == nil ? Color.clear : Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SnapshotDetailView: View {
    @Environment(\.portfolio) private var store
    let snapshot: Snapshot

    var body: some View {
        let prev = store.snapshot(before: snapshot)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("淨資產").font(.subheadline).foregroundStyle(.secondary)
                    MoneyText(value: store.netWorth(snapshot))
                        .font(.system(size: 34, weight: .regular))
                    if let prev {
                        let old = store.netWorth(prev)
                        DeltaBadge(delta: store.netWorth(snapshot) - old, base: old)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("報價") {
                ForEach(Quote.allCases) { q in
                    let v = snapshot.quotes[q] ?? 0
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text(Fmt.number(v)).monospacedDigit()
                            if let p = prev?.quotes[q], p != 0 {
                                Text(Fmt.percent((v - p) / p))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(store.deltaColor(v - p))
                            }
                        }
                    } label: {
                        Label(q.title, systemImage: q.symbol)
                    }
                }
            }

            ForEach(store.activeCategories) { cat in
                Section {
                    ForEach(store.accounts(in: cat).filter { snapshot.amounts[$0.id] != nil || prev?.amounts[$0.id] != nil }) { a in
                        AccountRow(account: a, snapshot: snapshot, previous: prev)
                    }
                } header: {
                    HStack {
                        Text(cat.title)
                        Spacer()
                        MoneyText(value: store.total(cat, in: snapshot))
                    }
                }
            }
        }
        .navigationTitle(snapshot.date.formatted(.dateTime.year().month().day()))
    }
}
