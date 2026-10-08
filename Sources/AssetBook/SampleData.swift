import Foundation

/// 第一次開啟、還沒有資料檔時的示範資料。數字皆為虛構。
extension PortfolioStore {
    static var sample: PortfolioStore {
        let cro = Account(name: "Crypto.com", note: "App", category: .crypto, currency: .usd, valuation: .holding(quote: .croUSD))
        let btc = Account(name: "比特幣", note: "冷錢包", category: .crypto, currency: .usd, valuation: .holding(quote: .btcUSD))

        let twStocks = Account(name: "台股", note: "富邦證券", category: .stocks, currency: .twd, valuation: .portfolio)
        let usStocks = Account(name: "美股", note: "Firstrade", category: .stocks, currency: .usd, valuation: .portfolio)

        let usdc = Account(name: "USDC", note: "穩定幣", category: .cash, currency: .usd)
        let esun = Account(name: "玉山銀行", category: .cash, currency: .twd)
        let line = Account(name: "LINE Bank", category: .cash, currency: .twd)
        let usdCash = Account(name: "美金存款", category: .cash, currency: .usd)
        let jpy = Account(name: "日幣現鈔", category: .cash, currency: .jpy)

        let card = Account(name: "中信信用卡", note: "本期應繳", category: .liability, currency: .twd)

        let accounts = [cro, btc, twStocks, usStocks, usdc, esun, line, usdCash, jpy, card]

        func day(_ m: Int, _ d: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: m, day: d))!
        }

        func tw(_ tsmc: Double, _ etf: Double) -> [Position] {
            [Position(symbol: "2330.TW", name: "台積電", shares: tsmc),
             Position(symbol: "0050.TW", name: "元大台灣50", shares: etf)]
        }
        func us(_ voo: Double, _ aapl: Double) -> [Position] {
            [Position(symbol: "VOO", name: "Vanguard S&P 500 ETF", shares: voo),
             Position(symbol: "AAPL", name: "Apple Inc.", shares: aapl)]
        }

        let columns: [(Date, [Quote: Double], [Account: Double], [Account: [Position]], [String: Double])] = [
            (day(9, 12),
             [.usdTWD: 31.64, .jpyTWD: 0.206, .btcUSD: 77_300, .croUSD: 0.058],
             [cro: 300_000, btc: 0.15, twStocks: 12_000, usStocks: 800, usdc: 5_000,
              esun: 420_000, line: 150_000, usdCash: 8_000, jpy: 80_000, card: 32_000],
             [twStocks: tw(200, 1_000), usStocks: us(20, 30)],
             ["2330.TW": 2_420, "0050.TW": 110.5, "VOO": 690.2, "AAPL": 318.4]),
            (day(9, 19),
             [.usdTWD: 31.78, .jpyTWD: 0.2026, .btcUSD: 81_000, .croUSD: 0.0587],
             [cro: 300_000, btc: 0.15, twStocks: 8_000, usStocks: 650, usdc: 4_500,
              esun: 395_000, line: 160_000, usdCash: 8_000, jpy: 80_000, card: 41_500],
             [twStocks: tw(200, 1_200), usStocks: us(20, 30)],
             ["2330.TW": 2_480, "0050.TW": 112.8, "VOO": 701.6, "AAPL": 325.1]),
            (day(9, 26),
             [.usdTWD: 31.73, .jpyTWD: 0.2016, .btcUSD: 84_000, .croUSD: 0.0666],
             [cro: 310_000, btc: 0.2, twStocks: 9_500, usStocks: 900, usdc: 4_500,
              esun: 380_000, line: 175_000, usdCash: 9_500, jpy: 80_000, card: 28_900],
             [twStocks: tw(200, 1_200), usStocks: us(22, 30)],
             ["2330.TW": 2_475, "0050.TW": 113.6, "VOO": 712.0, "AAPL": 331.9]),
        ]

        let snapshots = columns.map { date, quotes, amounts, holdings, prices in
            Snapshot(date: date, quotes: quotes,
                     amounts: Dictionary(uniqueKeysWithValues: amounts.map { ($0.key.id, $0.value) }),
                     holdings: Dictionary(uniqueKeysWithValues: holdings.map { ($0.key.id, $0.value) }),
                     stockPrices: prices)
        }
        return PortfolioStore(accounts: accounts, snapshots: snapshots)
    }
}
