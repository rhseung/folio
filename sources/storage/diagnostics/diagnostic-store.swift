import FolioDomain
import Foundation

// 이 기기의 MetricKit 보고를 둔다. GIST 폴더가 아니라 기기마다 따로 두는 폴더라서 앱이 자리를 정해 준다(`LocalFolders`).
public struct DiagnosticStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    static let prefix = "report-"  // strings: data, file name
    var seenURL: URL { url.appending(path: "seen.json") }

    struct Seen: Codable {
        var schemaVersion = 1
        var through: Date
    }

    public func add(_ records: [DiagnosticRecord]) throws {
        guard !records.isEmpty else { return }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for record in records {
            try DiagnosticExport.encoder.encode(record).write(to: url.appending(path: "\(Self.prefix)\(record.id).json"), options: .atomic)
        }
    }

    // 읽지 못하는 파일은 건너뛴다. 보고 하나가 깨져도 나머지는 보여야 한다.
    public func all() -> [DiagnosticRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix(Self.prefix) && $0.pathExtension == "json" }
            .compactMap { try? DiagnosticExport.decoder.decode(DiagnosticRecord.self, from: Data(contentsOf: $0)) }
            .sorted { ($0.span.end, $0.received) > ($1.span.end, $1.received) }
    }

    public var seenThrough: Date? {
        (try? Data(contentsOf: seenURL)).flatMap { try? DiagnosticExport.decoder.decode(Seen.self, from: $0).through }
    }

    public func markSeen(through date: Date) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try DiagnosticExport.encoder.encode(Seen(through: date)).write(to: seenURL, options: .atomic)
    }

    public func removeAll() throws {
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(Self.prefix) { try FileManager.default.removeItem(at: file) }
    }
}
