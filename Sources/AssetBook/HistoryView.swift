import SwiftUI

struct HistoryView: View {
    @Environment(\.portfolio) private var store
    @State private var pendingDelete: Snapshot?

    var body: some View {
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
        .navigationTitle("歷史紀錄")
        .navigationDestination(for: Snapshot.self) { SnapshotDetailView(snapshot: $0) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
                        .font(.system(size: 34, weight: .bold, design: .rounded))
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
