import FolioDomain
import Foundation

extension Sequence<LoggedEvent> {
    public func events<E: LogEvent>(_: E.Type) -> [(at: Date, event: E)] {
        compactMap { e in (try? e.decode(E.self)).flatMap { $0 }.map { (at: e.at, event: $0) } }
    }
}

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
