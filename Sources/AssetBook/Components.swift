import SwiftUI

// MARK: - 數字格式

enum Fmt {
    static func money(_ v: Double, _ c: Currency, digits: Int? = nil) -> String {
        let d = digits ?? c.fractionDigits
        let body = abs(v).formatted(.number.precision(.fractionLength(d)))
        return (v < 0 ? "−" : "") + c.symbol + body
    }

    static func signedMoney(_ v: Double, _ c: Currency) -> String {
        (v > 0 ? "+" : "") + money(v, c)
    }

    static func number(_ v: Double, digits: ClosedRange<Int> = 0...8) -> String {
        v.formatted(.number.precision(.fractionLength(digits)))
    }

    static func percent(_ v: Double) -> String {
        // 四捨五入後是 0 的就顯示 0.0%，避免出現「-0.0%」
        if abs(v) < 0.0005 { return 0.0.formatted(.percent.precision(.fractionLength(1))) }
        return (v > 0 ? "+" : "") + v.formatted(.percent.precision(.fractionLength(1)))
    }

    /// 圖表座標軸用：1,099萬、1.1億
    static func wan(_ v: Double) -> String {
        let a = abs(v)
        let sign = v < 0 ? "−" : ""
        if a >= 100_000_000 { return sign + (a / 100_000_000).formatted(.number.precision(.fractionLength(0...2))) + "億" }
        if a >= 10_000 { return sign + (a / 10_000).formatted(.number.precision(.fractionLength(0))) + "萬" }
        return sign + a.formatted(.number.precision(.fractionLength(0)))
    }

    /// 本地時區的日期，例如 2026-09-26（ISO 8601 格式預設是 UTC，台灣凌晨會變成前一天）
    static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// 解析使用者輸入，允許千分位逗號與空白。
    static func parse(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "−", with: "-")
        return cleaned.isEmpty ? nil : Double(cleaned)
    }
}

// MARK: - 平台顏色

extension Color {
    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

// MARK: - 金額（支援隱藏）

struct MoneyText: View {
    @Environment(\.portfolio) private var store
    let value: Double
    var currency: Currency = .twd
    var digits: Int? = nil

    var body: some View {
        Text(store.hideAmounts ? "••••••" : Fmt.money(value, currency, digits: digits))
            .monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(.snappy, value: value)
    }
}

// MARK: - 漲跌

extension PortfolioStore {
    func deltaColor(_ v: Double) -> Color {
        if v == 0 { return .secondary }
        return (v > 0) == redMeansUp ? .red : .green
    }
}

/// 膠囊樣式的漲跌標籤：▲ NT$374,281 (+3.5%)
struct DeltaBadge: View {
    @Environment(\.portfolio) private var store
    let delta: Double
    let base: Double
    var currency: Currency = .twd

    private var pct: Double? { base == 0 ? nil : delta / abs(base) }

    var body: some View {
        let color = store.deltaColor(delta)
        HStack(spacing: 4) {
            Image(systemName: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "equal")
                .font(.caption.weight(.bold))
            if !store.hideAmounts {
                Text(Fmt.money(abs(delta), currency))
            }
            if let pct {
                Text(store.hideAmounts ? Fmt.percent(pct) : "(\(Fmt.percent(pct)))")
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// 列表中使用的小型漲跌文字
struct DeltaText: View {
    @Environment(\.portfolio) private var store
    let delta: Double
    var base: Double? = nil
    var currency: Currency = .twd
    var showPercentOnly = false

    var body: some View {
        Group {
            // 上次金額太小或變動超過 ±100% 時，百分比沒有參考價值，改顯示金額
            if showPercentOnly || store.hideAmounts, let base, base != 0,
               store.hideAmounts || (abs(base) >= 1000 && abs(delta / base) <= 1) {
                Text(Fmt.percent(delta / abs(base)))
            } else if store.hideAmounts {
                Text(delta > 0 ? "▲" : delta < 0 ? "▼" : "—")
            } else {
                Text(Fmt.signedMoney(delta, currency))
            }
        }
        .monospacedDigit()
        .foregroundStyle(store.deltaColor(delta))
    }
}

// MARK: - 卡片

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Label(title, systemImage: systemImage ?? "")
                    .labelStyle(TitleOnlyIfNoIcon(hasIcon: systemImage != nil))
                    .font(.headline)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct TitleOnlyIfNoIcon: LabelStyle {
    let hasIcon: Bool
    func makeBody(configuration: Configuration) -> some View {
        if hasIcon { Label(configuration) } else { configuration.title }
    }
}

// MARK: - 共用工具列按鈕

// 工具列項目在 macOS 上不一定繼承 environment，所以明確傳入 store。
struct UpdateToolbarButton: View {
    let store: PortfolioStore
    var body: some View {
        Button {
            store.isUpdating = true
        } label: {
            Label("更新資產", systemImage: "square.and.pencil")
        }
        .help("輸入最新的餘額與報價（⌘U）")
    }
}

struct PrivacyToolbarButton: View {
    @Bindable var store: PortfolioStore
    var body: some View {
        Toggle(isOn: $store.hideAmounts) {
            Label("隱藏金額", systemImage: store.hideAmounts ? "eye.slash" : "eye")
        }
        .toggleStyle(.button)
        .help("隱藏所有金額（⇧⌘H）")
    }
}
