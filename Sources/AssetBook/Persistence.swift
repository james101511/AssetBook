import SwiftUI
import UniformTypeIdentifiers

/// 存檔內容：整份資料就是一個 JSON 檔。
struct StoredData: Codable {
    var version = 1
    var accounts: [Account]
    var snapshots: [Snapshot]
    var settings: Settings

    struct Settings: Codable {
        var redMeansUp: Bool
        var hideAmounts: Bool
        var autoFetchQuotes: Bool

        init(redMeansUp: Bool, hideAmounts: Bool, autoFetchQuotes: Bool) {
            self.redMeansUp = redMeansUp
            self.hideAmounts = hideAmounts
            self.autoFetchQuotes = autoFetchQuotes
        }

        // 舊版檔案沒有的欄位用預設值，避免讀檔失敗
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            redMeansUp = try c.decodeIfPresent(Bool.self, forKey: .redMeansUp) ?? true
            hideAmounts = try c.decodeIfPresent(Bool.self, forKey: .hideAmounts) ?? false
            autoFetchQuotes = try c.decodeIfPresent(Bool.self, forKey: .autoFetchQuotes) ?? true
        }
    }
}

/// 把資料存在 Application Support/AssetBook/data.json。
/// 每次寫入前會把舊檔複製到 backups/，保留最近 30 份。
struct Persistence {
    let directory: URL
    var maxBackups = 30

    var fileURL: URL { directory.appending(path: "data.json") }
    var backupsURL: URL { directory.appending(path: "backups", directoryHint: .isDirectory) }

    /// 可用環境變數 ASSETBOOK_DATA_DIR 指定其他資料夾（測試用）。
    static var `default`: Persistence {
        if let custom = ProcessInfo.processInfo.environment["ASSETBOOK_DATA_DIR"] {
            return Persistence(directory: URL(fileURLWithPath: custom, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return Persistence(directory: base.appending(path: "AssetBook", directoryHint: .isDirectory))
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// 檔案不存在時回傳 nil；檔案壞掉時丟出錯誤。
    func load() throws -> StoredData? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Self.decoder.decode(StoredData.self, from: Data(contentsOf: fileURL))
    }

    func save(_ data: StoredData) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try backup()
        try Self.encoder.encode(data).write(to: fileURL, options: .atomic)
    }

    /// 把目前的 data.json 複製一份到 backups/，並刪掉太舊的備份。
    func backup() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        try fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        let t = Calendar.current.dateComponents([.hour, .minute, .second], from: .now)
        let stamp = Fmt.day(.now) + String(format: "T%02d%02d%02d", t.hour!, t.minute!, t.second!)
        let dest = backupsURL.appending(path: "data-\(stamp).json")
        try? fm.removeItem(at: dest)
        try fm.copyItem(at: fileURL, to: dest)

        let old = try fm.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(maxBackups)
        for url in old { try? fm.removeItem(at: url) }
    }

    /// 讀不了的檔案改名保留，避免被新資料覆蓋。
    func quarantine() -> URL? {
        let dest = directory.appending(path: "data.broken-\(Int(Date.now.timeIntervalSince1970)).json")
        return (try? FileManager.default.moveItem(at: fileURL, to: dest)) != nil ? dest : nil
    }
}

// MARK: - 匯出／匯入用的文件

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - JSON 格式

// 讓 [Quote: Double] 編碼成 {"usdTWD": 31.7} 而不是陣列
extension Quote: CodingKeyRepresentable {}

extension Snapshot {
    private enum CodingKeys: String, CodingKey { case id, date, quotes, amounts, holdings, stockPrices }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode([String: Double].self, forKey: .amounts)
        // 舊版檔案沒有持股資料
        let rawHoldings = try c.decodeIfPresent([String: [Position]].self, forKey: .holdings) ?? [:]
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  date: try c.decode(Date.self, forKey: .date),
                  quotes: try c.decode([Quote: Double].self, forKey: .quotes),
                  amounts: Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } }),
                  holdings: Dictionary(uniqueKeysWithValues: rawHoldings.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } }),
                  stockPrices: try c.decodeIfPresent([String: Double].self, forKey: .stockPrices) ?? [:])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(quotes, forKey: .quotes)
        try c.encode(Dictionary(uniqueKeysWithValues: amounts.map { ($0.key.uuidString, $0.value) }), forKey: .amounts)
        if !holdings.isEmpty {
            try c.encode(Dictionary(uniqueKeysWithValues: holdings.map { ($0.key.uuidString, $0.value) }), forKey: .holdings)
            try c.encode(stockPrices, forKey: .stockPrices)
        }
    }
}
