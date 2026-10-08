import SwiftUI

// MARK: - 幣別

enum Currency: String, CaseIterable, Identifiable, Codable, Hashable {
    case twd = "TWD", usd = "USD", jpy = "JPY"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .twd: "NT$"
        case .usd: "US$"
        case .jpy: "¥"
        }
    }

    var name: String {
        switch self {
        case .twd: "新台幣"
        case .usd: "美元"
        case .jpy: "日圓"
        }
    }

    var fractionDigits: Int { self == .usd ? 2 : 0 }

    var tint: Color {
        switch self {
        case .twd: .indigo
        case .usd: .teal
        case .jpy: .pink
        }
    }
}

// MARK: - 資產分類

enum AssetCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case crypto, stocks, cash, liability

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crypto: "加密貨幣"
        case .stocks: "股票"
        case .cash: "現金與存款"
        case .liability: "負債"
        }
    }

    var symbol: String {
        switch self {
        case .crypto: "bitcoinsign.circle.fill"
        case .stocks: "chart.line.uptrend.xyaxis.circle.fill"
        case .cash: "banknote.fill"
        case .liability: "creditcard.fill"
        }
    }

    var tint: Color {
        switch self {
        case .crypto: .orange
        case .stocks: .blue
        case .cash: .green
        case .liability: .red
        }
    }

    /// 負債以正數輸入（應繳金額），計算淨值時扣除。
    var isLiability: Bool { self == .liability }

    /// 新增按鈕上的文字
    var addTitle: String { self == .liability ? "新增信用卡" : "新增帳戶" }

    var namePrompt: String {
        switch self {
        case .crypto: "例如：Binance"
        case .stocks: "例如：富邦證券"
        case .cash: "例如：玉山銀行"
        case .liability: "例如：國泰 CUBE 卡"
        }
    }
}

// MARK: - 市場報價

/// 每次更新時需要填的報價：匯率（以台幣計）與加密貨幣價格（以美元計）。
enum Quote: String, CaseIterable, Identifiable, Codable, Hashable {
    case usdTWD, jpyTWD, btcUSD, croUSD

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usdTWD: "美元匯率"
        case .jpyTWD: "日圓匯率"
        case .btcUSD: "比特幣"
        case .croUSD: "Cronos"
        }
    }

    var unit: String {
        switch self {
        case .usdTWD: "TWD/USD"
        case .jpyTWD: "TWD/JPY"
        case .btcUSD, .croUSD: "USD"
        }
    }

    /// 以這個報價計價的資產代號（數量 × 價格）。
    var assetSymbol: String? {
        switch self {
        case .btcUSD: "BTC"
        case .croUSD: "CRO"
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .usdTWD: "dollarsign.circle"
        case .jpyTWD: "yensign.circle"
        case .btcUSD: "bitcoinsign.circle"
        case .croUSD: "c.circle"
        }
    }

    /// 自動帶入報價時保留的小數位數
    var liveFractionDigits: Int {
        switch self {
        case .usdTWD: 4
        case .jpyTWD: 6
        case .btcUSD: 0
        case .croUSD: 5
        }
    }

    static var holdable: [Quote] { allCases.filter { $0.assetSymbol != nil } }
}

// MARK: - 帳戶

enum Valuation: Codable, Hashable {
    /// 直接輸入餘額（以帳戶幣別計）。
    case balance
    /// 輸入持有數量，價值 = 數量 × 報價（美元）。
    case holding(quote: Quote)
    /// 股票持股明細：價值 = Σ 股數 × 股價 ＋ 帳戶現金
    case portfolio
}

struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var note: String
    var category: AssetCategory
    var currency: Currency
    var valuation: Valuation
    /// 封存：不再出現在更新畫面與帳戶列表，但保留歷史紀錄
    var isArchived: Bool
    /// nil 表示依名稱自動配對（見 IconCatalog）
    var icon: AccountIcon?

    init(id: UUID = UUID(), name: String, note: String = "", category: AssetCategory,
         currency: Currency, valuation: Valuation = .balance, isArchived: Bool = false,
         icon: AccountIcon? = nil) {
        self.id = id
        self.name = name
        self.note = note
        self.category = category
        self.currency = currency
        self.valuation = valuation
        self.isArchived = isArchived
        self.icon = icon
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, note, category, currency, valuation, isArchived, icon
    }

    // 舊版資料檔沒有 isArchived，預設為 false
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        category = try c.decode(AssetCategory.self, forKey: .category)
        currency = try c.decode(Currency.self, forKey: .currency)
        valuation = try c.decode(Valuation.self, forKey: .valuation)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        icon = try c.decodeIfPresent(AccountIcon.self, forKey: .icon)
    }

    /// 頭像上的字：持有幣種用代號（BTC），短的英文縮寫整個顯示（USDC），其他取第一個字（樂、K）
    var monogram: String {
        if case .holding(let q) = valuation, let s = q.assetSymbol { return s }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 4, trimmed.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }), !trimmed.isEmpty {
            return trimmed
        }
        return trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    /// 輸入欄位的單位，例如「CRO」、「USD」。
    var inputUnit: String {
        if case .holding(let q) = valuation, let s = q.assetSymbol { return s }
        return currency.rawValue
    }

    var inputFractionDigits: ClosedRange<Int> {
        if case .holding = valuation { return 0...8 }
        return 0...currency.fractionDigits
    }

    var isPortfolio: Bool {
        if case .portfolio = valuation { return true }
        return false
    }
}

// MARK: - 快照（每次更新的一欄）

/// 一檔持股
struct Position: Codable, Hashable, Identifiable {
    var id: String { symbol }
    /// Yahoo 格式代號，例如 2330.TW、NVDA
    var symbol: String
    var name: String
    var shares: Double
}

struct Snapshot: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var quotes: [Quote: Double]
    /// 帳戶 id → 餘額、持有數量，或持股帳戶的現金
    var amounts: [UUID: Double]
    /// 持股帳戶 id → 當時的持股
    var holdings: [UUID: [Position]]
    /// 代號 → 當時的股價（以該股票的幣別計）
    var stockPrices: [String: Double]

    init(id: UUID = UUID(), date: Date, quotes: [Quote: Double], amounts: [UUID: Double],
         holdings: [UUID: [Position]] = [:], stockPrices: [String: Double] = [:]) {
        self.id = id
        self.date = date
        self.quotes = quotes
        self.amounts = amounts
        self.holdings = holdings
        self.stockPrices = stockPrices
    }
}
