import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 匯出成試算表：日期為欄、項目往下排，分區塊並附小計，結構和原本的試算表相同。
/// 可存成 CSV（Google 試算表「檔案 › 匯入」），或複製成 TSV 直接貼上。
enum SheetExport {
    static func rows(_ store: PortfolioStore) -> [[String]] {
        let snaps = store.snapshots
        var rows: [[String]] = [["項目"] + snaps.map { date($0.date) }]

        /// 輸入的數字（數量、股數、價格、餘額）保留原樣；算出來的價值與小計四捨五入到 2 位
        func row(_ title: String, computed: Bool = false, _ value: (Snapshot) -> Double?) {
            rows.append([title] + snaps.map { s in
                value(s).map { number(computed ? ($0 * 100).rounded() / 100 : $0) } ?? ""
            })
        }
        func section(_ title: String) { rows.append(["【\(title)】"]) }
        func blank() { rows.append([""]) }

        section("市場報價")
        for q in Quote.allCases {
            row("\(q.title) (\(q.unit))") { $0.quotes[q] }
        }
        blank()

        for cat in AssetCategory.allCases {
            // 只列出在這些紀錄中有資料的帳戶（含已封存）
            let accounts = store.accounts(in: cat).filter { a in
                snaps.contains { $0.amounts[a.id] != nil || !($0.holdings[a.id] ?? []).isEmpty }
            }
            guard !accounts.isEmpty else { continue }
            section(cat.title)

            for a in accounts {
                let cur = a.currency.rawValue
                switch a.valuation {
                case .holding:
                    row("\(a.name) 數量 (\(a.inputUnit))") { $0.amounts[a.id] }
                    row("\(a.name) 價值 (\(cur))", computed: true) { store.nativeValue(of: a, in: $0) }
                case .portfolio:
                    for p in positions(of: a, in: snaps) {
                        let label = "\(a.name) · \(StockService.displaySymbol(p.symbol)) \(p.name)"
                        row("\(label) 股數") { s in s.holdings[a.id]?.first { $0.symbol == p.symbol }?.shares }
                        row("\(label) 股價 (\(cur))") { s in
                            s.holdings[a.id]?.contains { $0.symbol == p.symbol } == true ? s.stockPrices[p.symbol] : nil
                        }
                    }
                    if snaps.contains(where: { ($0.amounts[a.id] ?? 0) != 0 }) {
                        row("\(a.name) 帳戶現金 (\(cur))") { $0.amounts[a.id] }
                    }
                    row("\(a.name) 合計 (\(cur))", computed: true) { store.nativeValue(of: a, in: $0) }
                case .balance:
                    // 負債以負數呈現，和原本試算表一樣
                    row("\(a.name) (\(cur))") { s in
                        s.amounts[a.id].map { cat.isLiability ? -$0 : $0 }
                    }
                }
            }
            row("\(cat.title) 小計 (TWD)", computed: true) { store.total(cat, in: $0) }
            blank()
        }

        section("總計")
        row("資產合計 (TWD)", computed: true) { store.grossAssets($0) }
        row("負債合計 (TWD)", computed: true) { store.total(.liability, in: $0) }
        row("淨資產 (TWD)", computed: true) { store.netWorth($0) }
        return rows
    }

    /// 持股帳戶出現過的所有股票，依第一次出現的順序
    private static func positions(of account: Account, in snaps: [Snapshot]) -> [Position] {
        var seen = Set<String>()
        var out: [Position] = []
        for s in snaps {
            for p in s.holdings[account.id] ?? [] where seen.insert(p.symbol).inserted {
                out.append(p)
            }
        }
        return out
    }

    /// 不加千分位，讓試算表當成數字
    private static func number(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...8)).grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func date(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!)
    }

    // MARK: 輸出格式

    static func csv(_ store: PortfolioStore) -> String {
        rows(store).map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func tsv(_ store: PortfolioStore) -> String {
        rows(store).map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    private static func csvField(_ s: String) -> String {
        guard s.contains(where: { ",\"\n\r".contains($0) }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// 複製成以 Tab 分隔的表格，在 Google 試算表點一格直接貼上即可
    static func copyToClipboard(_ store: PortfolioStore) {
        let text = tsv(store)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    /// CSV 檔內容：UTF-8 加 BOM，Google 試算表和 Excel 都能正確讀中文
    static func csvData(_ store: PortfolioStore) -> Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(csv(store).utf8)
    }

    static var defaultFilename: String { "AssetBook-試算表-\(Fmt.day(.now))" }
}
