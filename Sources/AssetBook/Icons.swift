import SwiftUI
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

// MARK: - 圖示種類

enum AccountIcon: Codable, Hashable {
    /// 文字縮寫（預設樣式）
    case monogram
    /// 從網站下載圖示，例如銀行、交易所
    case website(domain: String)
    /// 加密貨幣圖示（CoinGecko id）
    case token(id: String)
    /// 國旗，例如台股、外幣現鈔
    case flag(region: String)
    /// 使用者自選的圖片
    case custom
}

extension Account {
    /// 沒有手動設定時，依名稱自動配對
    var effectiveIcon: AccountIcon { icon ?? IconCatalog.suggestion(for: self) }
}

// MARK: - 內建對照表

enum IconCatalog {
    struct Token: Hashable { let symbol: String; let id: String; let names: [String] }
    struct Site { let keywords: [String]; let domain: String }

    static let tokens: [Token] = [
        Token(symbol: "BTC", id: "bitcoin", names: ["比特幣", "bitcoin"]),
        Token(symbol: "ETH", id: "ethereum", names: ["以太幣", "以太坊", "ethereum"]),
        Token(symbol: "CRO", id: "crypto-com-chain", names: ["cronos"]),
        Token(symbol: "USDC", id: "usd-coin", names: []),
        Token(symbol: "USDT", id: "tether", names: ["泰達幣"]),
        Token(symbol: "SOL", id: "solana", names: ["solana"]),
        Token(symbol: "BNB", id: "binancecoin", names: []),
        Token(symbol: "XRP", id: "ripple", names: ["瑞波幣"]),
        Token(symbol: "DOGE", id: "dogecoin", names: ["狗狗幣"]),
        Token(symbol: "ADA", id: "cardano", names: ["cardano"]),
    ]

    /// 台灣常見銀行、券商與交易所。關鍵字比對名稱與備註（不分大小寫）。
    static let sites: [Site] = [
        Site(keywords: ["將來"], domain: "www.nextbank.com.tw"),
        Site(keywords: ["樂天", "rakuten"], domain: "www.rakuten-bank.com.tw"),
        Site(keywords: ["richart"], domain: "richart.tw"),
        Site(keywords: ["台新"], domain: "www.taishinbank.com.tw"),
        Site(keywords: ["永豐", "sinopac", "dawho", "大戶"], domain: "bank.sinopac.com"),
        Site(keywords: ["國泰", "cube", "cathay"], domain: "www.cathaybk.com.tw"),
        Site(keywords: ["玉山", "esun"], domain: "www.esunbank.com"),
        Site(keywords: ["中信", "中國信託", "ctbc"], domain: "www.ctbcbank.com"),
        Site(keywords: ["富邦", "fubon"], domain: "www.fubon.com"),
        Site(keywords: ["台灣銀行", "臺灣銀行", "台銀"], domain: "www.bot.com.tw"),
        Site(keywords: ["兆豐"], domain: "www.megabank.com.tw"),
        Site(keywords: ["第一銀行", "一銀"], domain: "www.firstbank.com.tw"),
        Site(keywords: ["華南"], domain: "www.hncb.com.tw"),
        Site(keywords: ["合庫", "合作金庫"], domain: "www.tcb-bank.com.tw"),
        Site(keywords: ["郵局", "中華郵政"], domain: "www.post.gov.tw"),
        Site(keywords: ["line bank", "連線銀行"], domain: "www.linebank.com.tw"),
        Site(keywords: ["王道", "o-bank"], domain: "www.o-bank.com"),
        Site(keywords: ["星展", "dbs"], domain: "www.dbs.com.tw"),
        Site(keywords: ["滙豐", "匯豐", "hsbc"], domain: "www.hsbc.com.tw"),
        Site(keywords: ["元大"], domain: "www.yuanta.com.tw"),
        Site(keywords: ["firstrade"], domain: "www.firstrade.com"),
        Site(keywords: ["interactive brokers", "盈透"], domain: "www.interactivebrokers.com"),
        Site(keywords: ["schwab", "嘉信"], domain: "www.schwab.com"),
        Site(keywords: ["kraken"], domain: "www.kraken.com"),
        Site(keywords: ["crypto.com"], domain: "crypto.com"),
        Site(keywords: ["binance", "幣安"], domain: "www.binance.com"),
        Site(keywords: ["coinbase"], domain: "www.coinbase.com"),
        Site(keywords: ["okx"], domain: "www.okx.com"),
        Site(keywords: ["bybit"], domain: "www.bybit.com"),
        Site(keywords: ["bitopro", "幣託"], domain: "www.bitopro.com"),
        Site(keywords: ["max", "maicoin"], domain: "max.maicoin.com"),
        Site(keywords: ["pionex", "派網"], domain: "www.pionex.com"),
    ]

    static let flags: [(region: String, name: String)] = [
        ("TW", "台灣"), ("US", "美國"), ("JP", "日本"), ("HK", "香港"), ("CN", "中國"),
        ("KR", "韓國"), ("SG", "新加坡"), ("GB", "英國"), ("EU", "歐盟"), ("AU", "澳洲"),
    ]

    static func flagEmoji(_ region: String) -> String {
        region.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map(String.init).joined()
    }

    static func region(for currency: Currency) -> String {
        switch currency {
        case .twd: "TW"
        case .usd: "US"
        case .jpy: "JP"
        }
    }

    static func tokenID(for quote: Quote) -> String? {
        switch quote {
        case .btcUSD: "bitcoin"
        case .croUSD: "crypto-com-chain"
        default: nil
        }
    }

    static func suggestion(for account: Account) -> AccountIcon {
        if case .holding(let q) = account.valuation, let id = tokenID(for: q) { return .token(id: id) }

        let name = account.name.lowercased().trimmingCharacters(in: .whitespaces)
        let haystack = name + " " + account.note.lowercased()
        if let t = tokens.first(where: { $0.symbol.lowercased() == name || $0.names.contains(name) }) {
            return .token(id: t.id)
        }
        if let s = sites.first(where: { $0.keywords.contains { haystack.contains($0) } }) {
            return .website(domain: s.domain)
        }
        if name.contains("台股") { return .flag(region: "TW") }
        if name.contains("美股") { return .flag(region: "US") }
        if name.contains("日股") { return .flag(region: "JP") }
        // 現金、現鈔用該幣別的國旗（台幣現金也有圖示）
        if name.contains("現金") || name.contains("現鈔") { return .flag(region: region(for: account.currency)) }
        if account.currency != .twd { return .flag(region: region(for: account.currency)) }
        return .monogram
    }

    /// 給設定畫面的說明，例如「網站 · www.cathaybk.com.tw」
    static func describe(_ icon: AccountIcon) -> String {
        switch icon {
        case .monogram: "文字縮寫"
        case .website(let d): "網站圖示 · \(d)"
        case .token(let id): "代幣 · \(tokens.first { $0.id == id }?.symbol ?? id)"
        case .flag(let r): "國旗 · \(flagEmoji(r)) \(flags.first { $0.region == r }?.name ?? r)"
        case .custom: "自訂圖片"
        }
    }
}

// MARK: - 下載與快取

struct LoadedIcon {
    let image: PlatformImage
    let pixelWidth: Int
}

/// 下載圖示並存在 Application Support/AssetBook/logos/，之後離線也能顯示。
@MainActor @Observable
final class IconLoader {
    static let shared = IconLoader()

    /// 自訂圖片或清除快取後遞增，讓頭像重新載入
    private(set) var revision = 0
    @ObservationIgnored private var memory: [String: LoadedIcon] = [:]
    @ObservationIgnored private var failed: Set<String> = []
    @ObservationIgnored private var inflight: [String: Task<LoadedIcon?, Never>] = [:]

    nonisolated static var directory: URL {
        Persistence.default.directory.appending(path: "logos", directoryHint: .isDirectory)
    }

    nonisolated static func key(for icon: AccountIcon, accountID: UUID) -> String? {
        switch icon {
        case .website(let d): "site-\(d)"
        case .token(let id): "token-\(id)"
        case .custom: "custom-\(accountID.uuidString)"
        case .monogram, .flag: nil
        }
    }

    nonisolated static func fileURL(_ key: String) -> URL {
        directory.appending(path: "\(key).png")
    }

    func cached(_ icon: AccountIcon, accountID: UUID) -> LoadedIcon? {
        Self.key(for: icon, accountID: accountID).flatMap { memory[$0] }
    }

    func load(_ icon: AccountIcon, accountID: UUID) async -> LoadedIcon? {
        guard let key = Self.key(for: icon, accountID: accountID) else { return nil }
        if let hit = memory[key] { return hit }
        if failed.contains(key) { return nil }
        if let task = inflight[key] { return await task.value }

        let task = Task<LoadedIcon?, Never> {
            if let data = try? Data(contentsOf: Self.fileURL(key)), let icon = IconImage.decode(data) {
                return icon
            }
            let downloaded: Data? = switch icon {
            case .website(let d): await IconFetcher.siteIcon(domain: d)
            case .token(let id): await IconFetcher.tokenIcon(id: id)
            default: nil
            }
            guard let downloaded, let png = IconImage.normalizedPNG(downloaded) else { return nil }
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? png.write(to: Self.fileURL(key), options: .atomic)
            return IconImage.decode(png)
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        if let result { memory[key] = result } else { failed.insert(key) }
        return result
    }

    /// 儲存自訂圖片（縮到 256px）
    func setCustom(_ data: Data, accountID: UUID) throws {
        guard let png = IconImage.normalizedPNG(data) else { throw CocoaError(.fileReadCorruptFile) }
        let key = "custom-\(accountID.uuidString)"
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try png.write(to: Self.fileURL(key), options: .atomic)
        memory[key] = IconImage.decode(png)
        failed.remove(key)
        revision += 1
    }

    /// 重新下載某個圖示
    func refresh(_ icon: AccountIcon, accountID: UUID) {
        guard let key = Self.key(for: icon, accountID: accountID), !key.hasPrefix("custom-") else { return }
        try? FileManager.default.removeItem(at: Self.fileURL(key))
        memory[key] = nil
        failed.remove(key)
        revision += 1
    }

    /// 清除所有下載的圖示（保留自訂圖片）
    func clearDownloaded() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        for f in files where !f.lastPathComponent.hasPrefix("custom-") { try? FileManager.default.removeItem(at: f) }
        memory = memory.filter { $0.key.hasPrefix("custom-") }
        failed = []
        revision += 1
    }

    nonisolated static func removeCustom(accountID: UUID) {
        try? FileManager.default.removeItem(at: fileURL("custom-\(accountID.uuidString)"))
    }
}

// MARK: - 圖片處理

enum IconImage {
    /// 取出最大的一張（.ico 內含多種尺寸），縮到最多 256px，轉成 PNG
    static func normalizedPNG(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 0 else { return nil }
        var best = 0, bestWidth = 0
        for i in 0..<count {
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
            if w > bestWidth { best = i; bestWidth = w }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, best, options as CFDictionary),
              cg.width >= 8 else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    static func decode(_ png: Data) -> LoadedIcon? {
        guard let src = CGImageSourceCreateWithData(png as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        #if os(macOS)
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #else
        let image = UIImage(cgImage: cg)
        #endif
        return LoadedIcon(image: image, pixelWidth: cg.width)
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

// MARK: - 下載來源

enum IconFetcher {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private static func get(_ url: URL) async -> (Data, URL)? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return (data, response.url ?? url)
    }

    static func tokenIcon(id: String) async -> Data? {
        struct Response: Decodable { struct Images: Decodable { let large: String }; let image: Images }
        let api = "https://api.coingecko.com/api/v3/coins/\(id)?localization=false&tickers=false&market_data=false&community_data=false&developer_data=false&sparkline=false"
        guard let (data, _) = await get(URL(string: api)!),
              let r = try? JSONDecoder().decode(Response.self, from: data),
              let url = URL(string: r.image.large) else { return nil }
        return await get(url)?.0
    }

    /// 依序嘗試：網站宣告的最大圖示 → apple-touch-icon → Google favicon 服務 → favicon.ico。
    /// 太小（< 64px）的先保留，找不到更好的才用。
    static func siteIcon(domain: String) async -> Data? {
        var candidates: [(url: URL, size: Int)] = []
        let hosts = domain.hasPrefix("www.") ? [domain] : [domain, "www.\(domain)"]
        var base: URL?
        for host in hosts {
            guard let (html, finalURL) = await get(URL(string: "https://\(host)/")!) else { continue }
            base = finalURL
            candidates += declaredIcons(in: String(decoding: html, as: UTF8.self), base: finalURL)
            break
        }
        // 首頁可能轉址到別的網域（例如國泰 → cathay-cube），兩邊都試
        let original = URL(string: "https://\(domain)/")!
        let roots = [original] + (base.map { $0.host == original.host ? [] : [$0] } ?? [])
        for root in roots {
            candidates.append((URL(string: "/apple-touch-icon.png", relativeTo: root)!.absoluteURL, 180))
            candidates.append((URL(string: "https://www.google.com/s2/favicons?domain=\(root.host ?? domain)&sz=128")!, 60))
            candidates.append((URL(string: "/favicon.ico", relativeTo: root)!.absoluteURL, 16))
        }

        var seen = Set<URL>()
        var fallback: (data: Data, width: Int)?
        for c in candidates.sorted(by: { $0.size > $1.size }) where seen.insert(c.url).inserted {
            guard let (data, _) = await get(c.url), let png = IconImage.normalizedPNG(data),
                  let decoded = IconImage.decode(png) else { continue }
            if decoded.pixelWidth >= 64 { return data }
            if decoded.pixelWidth > (fallback?.width ?? 0) { fallback = (data, decoded.pixelWidth) }
        }
        return fallback?.data
    }

    /// 解析 <link rel="icon" | "apple-touch-icon" ...>
    private static func declaredIcons(in html: String, base: URL) -> [(url: URL, size: Int)] {
        guard let tagRegex = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive),
              let attrRegex = try? NSRegularExpression(pattern: "([a-zA-Z-]+)\\s*=\\s*[\"']([^\"']*)[\"']") else { return [] }
        let ns = html as NSString
        var result: [(URL, Int)] = []
        for tag in tagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let t = ns.substring(with: tag.range) as NSString
            var attrs: [String: String] = [:]
            for a in attrRegex.matches(in: t as String, range: NSRange(location: 0, length: t.length)) {
                attrs[t.substring(with: a.range(at: 1)).lowercased()] = t.substring(with: a.range(at: 2))
            }
            guard let rel = attrs["rel"]?.lowercased(), rel.contains("icon"), !rel.contains("mask"),
                  let href = attrs["href"], !href.lowercased().hasSuffix(".svg"),
                  let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            let declared = attrs["sizes"].flatMap { Int($0.lowercased().split(separator: "x").first ?? "") }
            let size = declared ?? (rel.contains("apple-touch") ? 180 : href.lowercased().contains(".ico") ? 32 : 48)
            result.append((url, size))
        }
        return result
    }
}

// MARK: - 頭像

/// 帳戶頭像：銀行／交易所圖示、代幣圖示、國旗，或分類顏色＋縮寫。
/// 外幣帳戶會在右下角加上小國旗。
struct AccountAvatar: View {
    let account: Account
    var size: CGFloat = 36
    /// 編輯畫面預覽尚未儲存的自訂圖片
    var preview: PlatformImage? = nil

    @State private var loaded: LoadedIcon?

    private var radius: CGFloat { size * 0.28 }

    var body: some View {
        let icon = account.effectiveIcon
        let loader = IconLoader.shared
        tile(icon)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(alignment: .bottomTrailing) { currencyBadge(icon) }
            .opacity(account.isArchived ? 0.5 : 1)
            .accessibilityHidden(true)
            .task(id: "\(icon)|\(account.id)|\(loader.revision)") {
                loaded = loader.cached(icon, accountID: account.id)
                if loaded == nil { loaded = await loader.load(icon, accountID: account.id) }
            }
    }

    @ViewBuilder private func tile(_ icon: AccountIcon) -> some View {
        switch icon {
        case .flag(let region):
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.quaternary)
                Text(IconCatalog.flagEmoji(region)).font(.system(size: size * 0.62))
            }
        case .website, .token, .custom:
            if let image = preview ?? loaded?.image {
                let width = preview.map { _ in 256 } ?? loaded?.pixelWidth ?? 256
                ZStack {
                    Color.white
                    Image(platformImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        // 低解析度的 favicon 不要放太大，避免模糊
                        .padding(width < 64 ? size * 0.22 : (isToken(icon) ? size * 0.06 : size * 0.12))
                }
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            } else {
                monogram
            }
        case .monogram:
            monogram
        }
    }

    private func isToken(_ icon: AccountIcon) -> Bool {
        if case .token = icon { return true }
        return false
    }

    private var monogram: some View {
        let text = account.monogram
        return Text(text)
            .font(.system(size: size * (text.count >= 4 ? 0.26 : text.count == 3 ? 0.3 : 0.44),
                          weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(account.category.tint.gradient)
    }

    @ViewBuilder private func currencyBadge(_ icon: AccountIcon) -> some View {
        let showsBadge: Bool = {
            guard account.currency != .twd, case .balance = account.valuation else { return false }
            switch icon {
            case .flag, .token: return false
            default: return true
            }
        }()
        if showsBadge {
            Text(IconCatalog.flagEmoji(IconCatalog.region(for: account.currency)))
                .font(.system(size: size * 0.3))
                .frame(width: size * 0.42, height: size * 0.42)
                .background(Circle().fill(Color.cardBackground))
                .offset(x: size * 0.14, y: size * 0.14)
        }
    }
}
