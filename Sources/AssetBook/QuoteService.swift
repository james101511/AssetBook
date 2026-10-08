import Foundation

/// 取得報價的結果。每個報價各自成功或失敗，部分失敗時仍回傳拿得到的數字。
struct LiveQuotes {
    var values: [Quote: Double] = [:]
    var sources: [Quote: String] = [:]
    var fetchedAt = Date.now
    var isHistorical = false
    var errors: [String] = []

    var missing: [Quote] { Quote.allCases.filter { values[$0] == nil } }
}

/// 免費、不需要 API key 的報價來源：
/// - 今天：匯率用 ExchangeRate-API（每日更新），幣價用 CoinGecko（即時）
/// - 過去日期（補登）：fawazahmed0/currency-api 的每日歷史資料
/// 主要來源失敗時，會改用 currency-api 補上缺的報價。
enum QuoteService {
    static func fetch(for date: Date) async -> LiveQuotes {
        if !Calendar.current.isDateInToday(date) {
            var result = LiveQuotes(isHistorical: true)
            await merge(into: &result, source: "currency-api") { try await currencyAPI(on: date) }
            return result
        }

        var result = LiveQuotes()
        async let fx = attempt { try await exchangeRateAPI() }
        async let crypto = attempt { try await coinGecko() }
        apply(await fx, to: &result, source: "ExchangeRate-API")
        apply(await crypto, to: &result, source: "CoinGecko")

        if !result.missing.isEmpty {
            await merge(into: &result, source: "currency-api") { try await currencyAPI(on: nil) }
        }
        return result
    }

    // MARK: 來源

    private static func exchangeRateAPI() async throws -> [Quote: Double] {
        struct Response: Decodable { let result: String; let rates: [String: Double] }
        let r: Response = try await get("https://open.er-api.com/v6/latest/USD")
        guard r.result == "success", let twd = r.rates["TWD"], let jpy = r.rates["JPY"] else {
            throw QuoteError.badResponse("ExchangeRate-API")
        }
        return [.usdTWD: twd, .jpyTWD: twd / jpy]
    }

    private static func coinGecko() async throws -> [Quote: Double] {
        let r: [String: [String: Double]] = try await get(
            "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,crypto-com-chain&vs_currencies=usd")
        var out: [Quote: Double] = [:]
        out[.btcUSD] = r["bitcoin"]?["usd"]
        out[.croUSD] = r["crypto-com-chain"]?["usd"]
        guard !out.isEmpty else { throw QuoteError.badResponse("CoinGecko") }
        return out
    }

    /// date 為 nil 時取最新一天。
    private static func currencyAPI(on date: Date?) async throws -> [Quote: Double] {
        struct Response: Decodable { let usd: [String: Double] }
        let tag = date.map(Fmt.day) ?? "latest"
        let r: Response = try await get("https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@\(tag)/v1/currencies/usd.json")
        // 這份資料以「1 美元可換多少」表示，幣價要取倒數
        var out: [Quote: Double] = [:]
        if let twd = r.usd["twd"] {
            out[.usdTWD] = twd
            if let jpy = r.usd["jpy"], jpy > 0 { out[.jpyTWD] = twd / jpy }
        }
        if let btc = r.usd["btc"], btc > 0 { out[.btcUSD] = 1 / btc }
        if let cro = r.usd["cro"], cro > 0 { out[.croUSD] = 1 / cro }
        guard !out.isEmpty else { throw QuoteError.badResponse("currency-api") }
        return out
    }

    // MARK: 工具

    enum QuoteError: LocalizedError {
        case badResponse(String)
        var errorDescription: String? {
            switch self { case .badResponse(let s): "\(s) 回傳的資料格式不正確" }
        }
    }

    private static func get<T: Decodable>(_ url: String) async throws -> T {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func attempt(_ work: () async throws -> [Quote: Double]) async -> Result<[Quote: Double], Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    private static func apply(_ r: Result<[Quote: Double], Error>, to result: inout LiveQuotes, source: String) {
        switch r {
        case .success(let values):
            for (q, v) in values where result.values[q] == nil {
                result.values[q] = v
                result.sources[q] = source
            }
        case .failure(let error):
            result.errors.append("\(source)：\(error.localizedDescription)")
        }
    }

    private static func merge(into result: inout LiveQuotes, source: String,
                              _ work: () async throws -> [Quote: Double]) async {
        apply(await attempt(work), to: &result, source: source)
    }
}
