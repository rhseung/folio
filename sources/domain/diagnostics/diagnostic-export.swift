import FolioCore
import Foundation

// 보고를 다른 곳에 넘길 때 쓰는 파일 하나다. 기기에 남긴 보고와 같은 꼴(`DiagnosticRecord`)을 모아 앱 버전과 함께 적는다.
public struct DiagnosticExport: Codable, Hashable, Sendable {
    public var schemaVersion = 1
    public var exported: Date
    public var appVersion: String
    public var records: [DiagnosticRecord]

    public init(exported: Date, appVersion: String, records: [DiagnosticRecord]) {
        self.exported = exported
        self.appVersion = appVersion
        self.records = records.sorted { $0.span.end < $1.span.end }
    }

    public func data() throws -> Data { try Self.encoder.encode(self) }

    public static func fileName(at date: Date, calendar: Calendar) -> String {
        "folio-diagnostics-\(LocalDate(date, in: calendar)).json"  // strings: data, file name
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
