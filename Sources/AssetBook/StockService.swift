import Foundation

/// 一檔股票的報價
struct StockQuote: Hashable {
    let symbol: String
    let name: String
    let price: Double
    let previousClose: Double?
    let currency: Currency?
    let source: String
}

/// 搜尋結果
struct SecurityResult: Identifiable, Hashable {
    var id: String { symbol }
    /// Yahoo 格式代號：2330.TW（上市）、6488.TWO（上櫃）、NVDA（美股）、7203.T（日股）
    let symbol: String
    let name: String
    let exchange: String
    let currency: Currency?
}

/// 股價來源：以 Yahoo Finance 為主；Yahoo 拒絕時（例如 429）自動改用
/// 台股 → 證交所即時資訊（上市、上櫃），美股 → CNBC。
enum StockService {
    // MARK: 代號

    /// 依代號判斷幣別
    static func currency(for symbol: String) -> Currency? {
        let s = symbol.uppercased()
        if s.hasSuffix(".TW") || s.hasSuffix(".TWO") { return .twd }
        if s.hasSuffix(".T") { return .jpy }
        if !s.contains(".") { return .usd }
        return nil
    }

    /// 顯示用代號：2330.TW → 2330
    static func displaySymbol(_ symbol: String) -> String {
        for suffix in [".TWO", ".TW"] where symbol.uppercased().hasSuffix(suffix) {
            return String(symbol.dropLast(suffix.count))
        }
        return symbol
    }

    static func isTaiwan(_ symbol: String) -> Bool { currency(for: symbol) == .twd }

    // MARK: 即時報價

    static func quotes(_ symbols: [String]) async -> (quotes: [String: StockQuote], errors: [String]) {
        let unique = Array(Set(symbols))
        guard !unique.isEmpty else { return ([:], []) }
        var result: [String: StockQuote] = [:]
        var errors: [String] = []

        if await YahooGate.shared.isOpen {
            await withTaskGroup(of: StockQuote?.self) { group in
                for s in unique { group.addTask { await yahooQuote(s) } }
                for await q in group { if let q { result[q.symbol] = q } }
            }
        }

        let missing = unique.filter { result[$0] == nil }
        let tw = missing.filter(isTaiwan)
        let us = missing.filter { currency(for: $0) == .usd }
        if !tw.isEmpty {
            let r = await twseQuotes(tw)
            result.merge(r) { a, _ in a }
            if r.isEmpty { errors.append("證交所：無法取得台股報價") }
        }
        if !us.isEmpty {
            let r = await cnbcQuotes(us)
            result.merge(r) { a, _ in a }
            if r.isEmpty { errors.append("CNBC：無法取得美股報價") }
        }
        let stillMissing = unique.filter { result[$0] == nil }
        if !stillMissing.isEmpty {
            errors.append("找不到 \(stillMissing.map(displaySymbol).joined(separator: "、")) 的股價")
        }
        return (result, errors)
    }

    /// 某一天（或之前最近一個交易日）的收盤價，用於補登過去日期
    static func closes(_ symbols: [String], on date: Date) async -> [String: Double] {
        var result: [String: Double] = [:]
        await withTaskGroup(of: (String, Double?).self) { group in
            for s in Set(symbols) {
                group.addTask {
                    if let p = await yahooClose(s, on: date) { return (s, p) }
                    if s.uppercased().hasSuffix(".TW") { return (s, await twseClose(s, on: date)) }
                    return (s, nil)
                }
            }
            for await (s, p) in group { if let p { result[s] = p } }
        }
        return result
    }

    // MARK: 搜尋

    static func search(_ query: String) async -> [SecurityResult] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        var results: [SecurityResult] = []
        if await YahooGate.shared.isOpen {
            results = await yahooSearch(q)
            // Yahoo 的台股名稱是英文，換成證交所／櫃買中心的中文名稱
            if results.contains(where: { isTaiwan($0.symbol) }) {
                let names = await TaiwanDirectory.shared.names()
                results = results.map { r in
                    guard let zh = names[r.symbol] else { return r }
                    return SecurityResult(symbol: r.symbol, name: zh, exchange: r.symbol.hasSuffix(".TWO") ? "上櫃" : "上市", currency: r.currency)
                }
            }
        }
        if results.isEmpty {
            async let tw = TaiwanDirectory.shared.search(q)
            async let us = cnbcSearch(q)
            results = await tw + us
        }
        var seen = Set<String>()
        return results.filter { seen.insert($0.symbol).inserted }
    }

    // MARK: - Yahoo

    static func yahooQuote(_ symbol: String) async -> StockQuote? {
        struct Response: Decodable {
            struct Chart: Decodable { let result: [Result]? }
            struct Result: Decodable { let meta: Meta }
            struct Meta: Decodable {
                let symbol: String
                let currency: String?
                let regularMarketPrice: Double?
                let chartPreviousClose: Double?
                let shortName: String?
                let longName: String?
            }
            let chart: Chart
        }
        let path = "https://query1.finance.yahoo.com/v8/finance/chart/\(escape(symbol))?range=1d&interval=1d"
        guard let r: Response = await yahooGet(path), let m = r.chart.result?.first?.meta,
              let price = m.regularMarketPrice else { return nil }
        return StockQuote(symbol: symbol, name: m.longName ?? m.shortName ?? displaySymbol(symbol), price: price,
                          previousClose: m.chartPreviousClose, currency: m.currency.flatMap(Currency.init(rawValue:)),
                          source: "Yahoo")
    }

    private static func yahooClose(_ symbol: String, on date: Date) async -> Double? {
        struct Response: Decodable {
            struct Chart: Decodable { let result: [Result]? }
            struct Result: Decodable { let timestamp: [Double]?; let indicators: Indicators }
            struct Indicators: Decodable { let quote: [Quote] }
            struct Quote: Decodable { let close: [Double?]? }
            let chart: Chart
        }
        guard await YahooGate.shared.isOpen else { return nil }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))!
        let start = Calendar.current.date(byAdding: .day, value: -10, to: end)!
        let path = "https://query1.finance.yahoo.com/v8/finance/chart/\(escape(symbol))?period1=\(Int(start.timeIntervalSince1970))&period2=\(Int(end.timeIntervalSince1970))&interval=1d"
        guard let r: Response = await yahooGet(path), let res = r.chart.result?.first,
              let closes = res.indicators.quote.first?.close else { return nil }
        return closes.compactMap { $0 }.last
    }

    private static func yahooSearch(_ q: String) async -> [SecurityResult] {
        struct Response: Decodable {
            struct Item: Decodable { let symbol: String; let shortname: String?; let longname: String?; let exchDisp: String?; let quoteType: String? }
            let quotes: [Item]
        }
        let path = "https://query1.finance.yahoo.com/v1/finance/search?q=\(escape(q))&quotesCount=12&newsCount=0"
        guard let r: Response = await yahooGet(path) else { return [] }
        return r.quotes
            .filter { ["EQUITY", "ETF", "MUTUALFUND"].contains($0.quoteType ?? "") }
            .map { SecurityResult(symbol: $0.symbol, name: $0.longname ?? $0.shortname ?? $0.symbol,
                                  exchange: $0.exchDisp ?? "", currency: currency(for: $0.symbol)) }
    }

    private static func yahooGet<T: Decodable>(_ url: String) async -> T? {
        guard let (data, status) = await fetch(url) else { return nil }
        if status == 429 || status == 401 {
            await YahooGate.shared.block()
            return nil
        }
        guard (200..<300).contains(status) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - 證交所（台股備援）

    /// 證交所即時資訊，一次查多檔；上市用 tse_、上櫃用 otc_
    private static func twseQuotes(_ symbols: [String]) async -> [String: StockQuote] {
        struct Response: Decodable {
            struct Item: Decodable { let c: String; let n: String?; let z: String?; let y: String?; let b: String?; let ex: String? }
            let msgArray: [Item]?
        }
        let channels = symbols.map { s -> String in
            let code = displaySymbol(s).lowercased()
            return s.uppercased().hasSuffix(".TWO") ? "otc_\(code).tw" : "tse_\(code).tw"
        }
        let url = "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=\(escape(channels.joined(separator: "|")))&json=1&delay=0"
        guard let (data, status) = await fetch(url), (200..<300).contains(status),
              let r = try? JSONDecoder().decode(Response.self, from: data) else { return [:] }
        var out: [String: StockQuote] = [:]
        for item in r.msgArray ?? [] {
            guard let symbol = symbols.first(where: { displaySymbol($0).uppercased() == item.c.uppercased() }) else { continue }
            let previous = item.y.flatMap(Double.init)
            // 盤中尚未成交時 z 為 "-"，改用最佳買價或昨收
            let price = item.z.flatMap(Double.init)
                ?? item.b?.split(separator: "_").first.flatMap { Double($0) }
                ?? previous
            guard let price else { continue }
            out[symbol] = StockQuote(symbol: symbol, name: item.n ?? item.c, price: price,
                                     previousClose: previous, currency: .twd, source: "證交所")
        }
        return out
    }

    /// 證交所個股月成交資訊（只有上市股票）
    private static func twseClose(_ symbol: String, on date: Date) async -> Double? {
        struct Response: Decodable { let stat: String; let data: [[String]]? }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let ymd = String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
        let url = "https://www.twse.com.tw/exchangeReport/STOCK_DAY?response=json&date=\(ymd)&stockNo=\(displaySymbol(symbol))"
        guard let (data, status) = await fetch(url), (200..<300).contains(status),
              let r = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        // 日期為民國年，例如 115/09/24
        let target = String(format: "%03d/%02d/%02d", c.year! - 1911, c.month!, c.day!)
        let rows = (r.data ?? []).filter { ($0.first ?? "") <= target }
        guard let row = rows.last, row.count > 6 else { return nil }
        return Double(row[6].replacingOccurrences(of: ",", with: ""))
    }

    // MARK: - CNBC（美股備援）

    private static func cnbcQuotes(_ symbols: [String]) async -> [String: StockQuote] {
        struct Response: Decodable {
            struct Result: Decodable { let FormattedQuote: [Item] }
            struct Item: Decodable { let symbol: String; let name: String?; let last: String?; let previous_day_closing: String?; let currencyCode: String? }
            let FormattedQuoteResult: Result
        }
        let joined = escape(symbols.joined(separator: "|"))
        let url = "https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol?symbols=\(joined)&requestMethod=itv&noform=1&partnerId=2&fund=1&exthrs=1&output=json"
        guard let (data, status) = await fetch(url), (200..<300).contains(status),
              let r = try? JSONDecoder().decode(Response.self, from: data) else { return [:] }
        func number(_ s: String?) -> Double? { s.flatMap { Double($0.replacingOccurrences(of: ",", with: "")) } }
        var out: [String: StockQuote] = [:]
        for item in r.FormattedQuoteResult.FormattedQuote {
            guard let symbol = symbols.first(where: { $0.uppercased() == item.symbol.uppercased() }),
                  let price = number(item.last) else { continue }
            out[symbol] = StockQuote(symbol: symbol, name: item.name ?? symbol, price: price,
                                     previousClose: number(item.previous_day_closing),
                                     currency: item.currencyCode.flatMap(Currency.init(rawValue:)), source: "CNBC")
        }
        return out
    }

    private static func cnbcSearch(_ q: String) async -> [SecurityResult] {
        struct Item: Decodable { let symbolName: String?; let companyName: String?; let exchangeName: String?; let countryCode: String?; let issueType: String? }
        // 中文或純數字查詢交給台股名錄
        guard q.allSatisfy({ $0.isASCII }), !q.allSatisfy(\.isNumber) else { return [] }
        let url = "https://symlookup.cnbc.com/symservice/symlookup.do?prefix=\(escape(q))&partnerid=20064&pgok=1&pgsize=12"
        guard let (data, status) = await fetch(url), (200..<300).contains(status),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        // 第一筆是統計資訊，其餘才是結果
        let items = raw.dropFirst().compactMap { dict -> Item? in
            guard let d = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? JSONDecoder().decode(Item.self, from: d)
        }
        return items
            .filter { $0.countryCode == "US" && ["STOCK", "FUND", "ETF"].contains($0.issueType ?? "") }
            .compactMap { i in
                guard let s = i.symbolName else { return nil }
                return SecurityResult(symbol: s, name: i.companyName ?? s, exchange: i.exchangeName ?? "", currency: .usd)
            }
    }

    // MARK: - 共用

    static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? s
    }

    static func fetch(_ url: String) async -> (Data, Int)? {
        guard let u = URL(string: url) else { return nil }
        var request = URLRequest(url: u, timeoutInterval: 10)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Yahoo 回傳 429 後暫停使用 10 分鐘，避免每次都白等
actor YahooGate {
    static let shared = YahooGate()
    private var blockedUntil: Date?

    var isOpen: Bool { blockedUntil.map { Date.now >= $0 } ?? true }

    func block() { blockedUntil = Date.now.addingTimeInterval(600) }
}

/// 台股名錄（證交所上市 + 櫃買中心上櫃），讓中文名稱也能搜尋。每次啟動下載一次。
actor TaiwanDirectory {
    static let shared = TaiwanDirectory()
    private var entries: [SecurityResult]?

    func search(_ q: String) async -> [SecurityResult] {
        let all = await load()
        let key = q.uppercased()
        let exact = all.filter { StockService.displaySymbol($0.symbol).uppercased() == key }
        let rest = all.filter { e in
            !exact.contains(e) &&
            (StockService.displaySymbol(e.symbol).uppercased().hasPrefix(key) || e.name.uppercased().contains(key))
        }
        return Array((exact + rest).prefix(12))
    }

    /// 代號 → 中文名稱
    func names() async -> [String: String] {
        Dictionary((await load()).map { ($0.symbol, $0.name) }) { a, _ in a }
    }

    private func load() async -> [SecurityResult] {
        if let entries { return entries }
        struct Listed: Decodable { let Code: String; let Name: String }
        struct OTC: Decodable { let SecuritiesCompanyCode: String; let CompanyName: String }
        async let listed = StockService.fetch("https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL")
        async let otc = StockService.fetch("https://www.tpex.org.tw/openapi/v1/tpex_mainboard_quotes")
        var out: [SecurityResult] = []
        if let (data, _) = await listed, let items = try? JSONDecoder().decode([Listed].self, from: data) {
            out += items.map { SecurityResult(symbol: "\($0.Code).TW", name: $0.Name, exchange: "上市", currency: .twd) }
        }
        if let (data, _) = await otc, let items = try? JSONDecoder().decode([OTC].self, from: data) {
            out += items.map { SecurityResult(symbol: "\($0.SecuritiesCompanyCode).TWO", name: $0.CompanyName, exchange: "上櫃", currency: .twd) }
        }
        if !out.isEmpty { entries = out }
        return out
    }
}
