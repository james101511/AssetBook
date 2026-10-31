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

// MARK: - 外觀

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: "自動"
        case .light: "淺色"
        case .dark: "深色"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// macOS 上 preferredColorScheme 切回「自動」時不會還原，所以直接設定整個 App 的外觀
    func apply() {
        #if os(macOS)
        switch self {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
        #endif
    }
}

// MARK: - 平台顏色

extension Color {
    /// 淺色：系統灰白；深色：石墨灰，卡片只比背景亮一階，深度靠細線而不是陰影
    static let groupedBackground = adaptive(light: nil, dark: 0x141415, system: .page)
    static let cardBackground = adaptive(light: nil, dark: 0x1B1B1D, system: .card)

    /// 側邊欄比頁面再深一點
    static let sidebarBackground = adaptive(light: nil, dark: 0x0F0F10, system: .sidebar)

    private enum SystemRole { case page, card, sidebar }

    private static func adaptive(light: UInt32?, dark: UInt32, system: SystemRole) -> Color {
        #if os(iOS)
        return Color(uiColor: UIColor { t in
            if t.userInterfaceStyle == .dark { return UIColor(hex: dark) }
            return system == .page ? .systemGroupedBackground : .secondarySystemGroupedBackground
        })
        #else
        return Color(nsColor: NSColor(name: nil) { a in
            if a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua { return NSColor(hex: dark) }
            switch system {
            case .page: return .windowBackgroundColor
            case .card: return .controlBackgroundColor
            case .sidebar: return NSColor.windowBackgroundColor.blended(withFraction: 0.04, of: .black) ?? .windowBackgroundColor
            }
        })
        #endif
    }
}

#if os(iOS)
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#else
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

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

/// 漲跌：↗ NT$374,281 (+3.5%)，純文字，不加底色
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
                .font(.caption.weight(.semibold))
            if !store.hideAmounts {
                Text(Fmt.money(abs(delta), currency))
            }
            if let pct {
                Text(store.hideAmounts ? Fmt.percent(pct) : "(\(Fmt.percent(pct)))")
            }
        }
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(color)
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
        .foregroundStyle(store.deltaColor(isFlat ? 0 : delta))
    }

    /// 只顯示百分比、而且四捨五入後是 0.0% 時，用灰色
    private var isFlat: Bool {
        guard showPercentOnly || store.hideAmounts, let base, base != 0 else { return false }
        return abs(delta / base) < 0.0005
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
                    .font(.headline.weight(.medium))
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            // 深度用細線，不用陰影
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
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
