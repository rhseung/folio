import FolioDomain
import Foundation

/// `data` stays raw so event types from newer app versions are read without loss.
public struct LoggedEvent: Sendable, Equatable {
    public var id: UUID
    public var at: Date
    public var device: DeviceID
    public var type: String
    public var data: JSONValue

    public func decode<E: LogEvent>(_: E.Type) throws -> E? {
        guard type == E.type else { return nil }
        return try JSONFormat.decoder.decode(E.self, from: JSONFormat.encoder.encode(data))
    }
}

extension Sequence<LoggedEvent> {
    /// A line that doesn't decode is skipped, so one bad line hides nothing else.
    public func events<E: LogEvent>(_: E.Type) -> [(at: Date, event: E)] {
        compactMap { e in (try? e.decode(E.self)).flatMap { $0 }.map { (at: e.at, event: $0) } }
    }
}

/// `.folio/logs/<device ID>.jsonl`. Each device appends only to its own file and never edits a line,
/// so two devices never write the same file (docs/SPEC.md "동기화와 충돌 방지").
public struct EventLog: Sendable {
    static let schemaVersion = 1

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    func fileURL(for device: DeviceID) -> URL {
        folder.appending(path: device.uuidString).appendingPathExtension(StandardLayout.logExtension)
    }

    private struct Line<Data: Codable>: Codable {
        var schemaVersion: Int
        var id: UUID
        var at: Date
        var device: DeviceID
        var type: String
        var data: Data
    }

    public func append<E: LogEvent>(_ event: E, device: DeviceID, at date: Date, id: UUID = UUID()) throws {
        let line = Line(schemaVersion: Self.schemaVersion, id: id, at: date, device: device, type: E.type, data: event)
        try CoordinatedFile.append(JSONFormat.lineEncoder.encode(line) + Data("\n".utf8), to: fileURL(for: device))
    }

    /// Lines that fail to parse (e.g. a write cut off mid-line) are skipped.
    public func readAll() throws -> [LoggedEvent] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == StandardLayout.logExtension }
        return try files.flatMap { file in
            try CoordinatedFile.read(file)
                .split(separator: UInt8(ascii: "\n"))
                .compactMap { try? JSONFormat.decoder.decode(Line<JSONValue>.self, from: Data($0)) }
                .map { LoggedEvent(id: $0.id, at: $0.at, device: $0.device, type: $0.type, data: $0.data) }
        }
        .sorted { ($0.at, $0.id.uuidString) < ($1.at, $1.id.uuidString) }
    }
}

public enum LocalDevice {
    static let key = "folio.deviceID"

    /// Stable per install and never synced, so each device keeps writing to its own log file.
    public static func id(in defaults: UserDefaults = .standard) -> DeviceID {
        if let stored = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) { return stored }
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}
