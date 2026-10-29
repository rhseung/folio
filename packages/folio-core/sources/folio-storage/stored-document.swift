import FolioDomain
import Foundation

public enum StorageError: Error, Equatable {
    case missingSchemaVersion(URL)
    case missingMigration(from: Int, URL)
    /// The file was written by a newer app version; saving could lose its changes.
    case newerSchema(found: Int, supported: Int, URL)
    case coordination(String)
}

/// A JSON file format. Bump `schemaVersion` and add a migration (from the old version, on raw JSON) whenever the shape changes.
public protocol StoredModel: Codable {
    static var schemaVersion: Int { get }
    static var migrations: [Int: @Sendable (inout JSONValue) throws -> Void] { get }
}

extension StoredModel {
    public static var migrations: [Int: @Sendable (inout JSONValue) throws -> Void] { [:] }
}

extension Transcript: StoredModel {
    public static let schemaVersion = 1
}

extension CourseFile: StoredModel {
    public static let schemaVersion = 2
    public static let migrations: [Int: @Sendable (inout JSONValue) throws -> Void] = [1: dropSessionKind]

    /// v1 sessions had a `kind` and a lab number. A session is now one class: `cancelled` is a flag, a lab is a unit
    /// the session links to, and recitations and makeups are plain sessions.
    static func dropSessionKind(_ raw: inout JSONValue) throws {
        guard case .array(var sessions)? = raw["sessions"] else { return }
        var labs: [(index: Int, number: Int)] = []
        var recitationWeeks: Set<JSONValue> = []
        for i in sessions.indices {
            let kind = sessions[i]["kind"]
            let number = sessions[i]["lab"]
            sessions[i]["kind"] = nil
            sessions[i]["lab"] = nil
            switch kind {
            case .string("cancelled"): sessions[i]["cancelled"] = .bool(true)
            // Keeps what the name `9주차 리시테이션` used to say.
            case .string("recitation"):
                if sessions[i]["topic"] == .string("") { sessions[i]["topic"] = .string("리시테이션") }
                if let week = sessions[i]["week"] { recitationWeeks.insert(week) }
            // A lab without a number keeps only the units it already links to: guessing one from its place among labs
            // linked a real session to the wrong lab.
            case .string("lab"):
                if case .number(let n)? = number { labs.append((i, Int(n))) }
            default: break
            }
        }
        // v1 left recitations out of a week's numbering, so their stored index trails the lectures'. Numbered in date
        // order, `2주차-2` is the class after `2주차-1`. The dates are one fixed ISO format, so they sort as strings.
        func date(_ i: Int) -> String { if case .string(let d)? = sessions[i]["date"] { d } else { "" } }
        for week in recitationWeeks {
            let inWeek = sessions.indices.filter { sessions[$0]["week"] == week }.sorted { date($0) < date($1) }
            for (n, i) in inWeek.enumerated() { sessions[i]["index"] = .number(Double(n + 1)) }
        }
        raw["sessions"] = .array(sessions)
        guard !labs.isEmpty else { return }

        var file = try JSONFormat.decoder.decode(CourseFile.self, from: JSONFormat.encoder.encode(raw))
        // By number, then date, so a lab's unit takes its title from its first session.
        for lab in labs.map({ (session: file.sessions[$0.index], number: $0.number) }).sorted(by: { ($0.number, $0.session.date) < ($1.number, $1.session.date) }) {
            let s = lab.session
            file.linkLab(lab.number, session: s.id, topic: s.topic, id: derivedID(s.id), device: s.updatedBy, at: s.updatedAt)
        }
        let encoded = try JSONFormat.decoder.decode(JSONValue.self, from: JSONFormat.encoder.encode(file))
        raw = JSONValue.preservingUnknownKeys(old: raw, new: encoded, model: file)
    }

    /// Reading a v1 file again before it is saved must make the same unit, so its id comes from the first lab session's.
    static func derivedID(_ id: UUID) -> UUID {
        var bytes = id.uuid
        bytes.15 ^= 0x5A
        return UUID(uuid: bytes)
    }
}

extension Catalog: StoredModel {
    public static let schemaVersion = 1
}

extension Settings: StoredModel {
    public static let schemaVersion = 1
}

extension QuizFile: StoredModel {
    public static let schemaVersion = 1
}

/// A model plus the raw JSON it was read from, so saving keeps keys this app version doesn't know.
public struct StoredDocument<Model: StoredModel> {
    public var model: Model
    public let fileVersion: Int
    private let raw: JSONValue?

    static var versionKey: String { "schemaVersion" }

    public init(new model: Model) {
        self.model = model
        self.fileVersion = Model.schemaVersion
        self.raw = nil
    }

    public var isReadOnly: Bool { fileVersion > Model.schemaVersion }

    public static func read(from url: URL) throws -> Self {
        var raw = try JSONFormat.decoder.decode(JSONValue.self, from: CoordinatedFile.read(url))
        guard case .number(let v)? = raw[versionKey] else { throw StorageError.missingSchemaVersion(url) }
        var version = Int(v)
        let fileVersion = version
        while version < Model.schemaVersion {
            guard let migrate = Model.migrations[version] else { throw StorageError.missingMigration(from: version, url) }
            try migrate(&raw)
            version += 1
        }
        let model = try JSONFormat.decoder.decode(Model.self, from: JSONFormat.encoder.encode(raw))
        return Self(model: model, fileVersion: fileVersion, raw: raw)
    }

    private init(model: Model, fileVersion: Int, raw: JSONValue) {
        self.model = model
        self.fileVersion = fileVersion
        self.raw = raw
    }

    public func write(to url: URL) throws {
        guard !isReadOnly else {
            throw StorageError.newerSchema(found: fileVersion, supported: Model.schemaVersion, url)
        }
        let encoded = try JSONFormat.decoder.decode(JSONValue.self, from: JSONFormat.encoder.encode(model))
        var merged = raw.map { JSONValue.preservingUnknownKeys(old: $0, new: encoded, model: model) } ?? encoded
        merged[Self.versionKey] = .number(Double(Model.schemaVersion))
        try CoordinatedFile.write(JSONFormat.encoder.encode(merged), to: url)
    }
}
