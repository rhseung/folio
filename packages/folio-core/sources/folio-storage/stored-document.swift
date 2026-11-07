import FolioDomain
import Foundation

public enum StorageError: Error, Equatable {
    case missingSchemaVersion(URL)
    case missingMigration(from: Int, URL)
    /// The file was written by a newer app version; saving could lose its changes.
    case newerSchema(found: Int, supported: Int, URL)
    case coordination(String)
    /// A text file in another encoding (a CP949 `.csv`). Read leniently and saved back, it would lose every byte that
    /// didn't decode, so it isn't read at all.
    case notUTF8(String)
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
    public static let schemaVersion = 2
    public static let migrations: [Int: @Sendable (inout JSONValue) throws -> Void] = [1: unfileCourses]

    /// v1 kept courses without a folder under `courses`. Every course now has a folder, so they wait under
    /// `unfiledCourses` for `transcript move`. The version stops an older app from adding new ones beside them.
    static func unfileCourses(_ raw: inout JSONValue) throws {
        let courses = raw["courses"]
        raw["courses"] = nil
        if case .array(let items)? = courses, !items.isEmpty { raw["unfiledCourses"] = .array(items) }
    }
}

extension CourseFile: StoredModel {
    public static let schemaVersion = 6
    public static let migrations: [Int: @Sendable (inout JSONValue) throws -> Void] = [
        1: dropSessionKind, 2: dropSessionIndex, 3: dropExamKind, 4: splitRolesByOrigin, 5: keepNoteLinksOnSessions,
    ]

    /// v5 kept a note's session twice, as the note's `sessionId` and the session's `roughNoteId`/`reviewNoteId`, and
    /// gave rough, review and exam notes a copy of their session's units or exam's scope that never followed later
    /// changes. The session now holds the link alone and those units are read from it. A note's `sessionId` is moved
    /// to its session when that slot is free and nothing else points at the note; a note a session points at takes
    /// that slot's kind (`import calendar` linked review notes without making them one); a second pointer at a note
    /// lets go of it, the first in the file keeping it. A pointer at a unit or exam note lets go too: that
    /// `import calendar` took any unlinked note, and making it a review note would drop the units its user chose.
    static func keepNoteLinksOnSessions(_ raw: inout JSONValue) throws {
        func id(_ value: JSONValue?) -> UUID? { if case .string(let s)? = value { UUID(uuidString: s) } else { nil } }
        let slots = [("roughNoteId", "rough"), ("reviewNoteId", "review")]
        var sessions: [JSONValue] = if case .array(let a)? = raw["sessions"] { a } else { [] }
        var notes: [JSONValue] = if case .array(let a)? = raw["notes"] { a } else { [] }
        var kindOf: [UUID: String] = [:]
        let kept: Set<String> = [NoteKind.unit.rawValue, NoteKind.examSummary.rawValue]
        let ownUnits = Set(notes.compactMap { n -> UUID? in
            guard case .string(let kind)? = n["kind"], kept.contains(kind) else { return nil }
            return id(n["id"])
        })

        for i in sessions.indices {
            for (key, kind) in slots {
                guard let note = id(sessions[i][key]) else { continue }
                if kindOf[note] == nil && !ownUnits.contains(note) {
                    kindOf[note] = kind
                } else {
                    sessions[i][key] = nil
                    if key == "reviewNoteId" { sessions[i]["reviewNoteDraft"] = nil }
                }
            }
        }
        for n in notes.indices {
            guard let note = id(notes[n]["id"]), kindOf[note] == nil, let session = id(notes[n]["sessionId"]),
                  case .string(let kind)? = notes[n]["kind"], let (key, _) = slots.first(where: { $0.1 == kind }),
                  let s = sessions.firstIndex(where: { id($0["id"]) == session }), id(sessions[s][key]) == nil else { continue }
            sessions[s][key] = .string(note.uuidString)
            kindOf[note] = kind
        }
        for n in notes.indices {
            if let note = id(notes[n]["id"]), let kind = kindOf[note] { notes[n]["kind"] = .string(kind) }
            if notes[n]["kind"] != .string(NoteKind.unit.rawValue) { notes[n]["unitIds"] = .array([]) }
            notes[n]["sessionId"] = nil
        }
        if raw["sessions"] != nil { raw["sessions"] = .array(sessions) }
        if raw["notes"] != nil { raw["notes"] = .array(notes) }
    }

    /// v4 roles mixed origin and purpose: `pastExam` for `Exams/Past`, `examPrep` for anything in an exam folder. Past
    /// exams now sit in `Inherited` and an exam folder holds only that exam's record, so the roles follow the folders.
    /// Files stay where they are; the cleanup plan moves them and marks past exam papers, which a user can review.
    static func splitRolesByOrigin(_ raw: inout JSONValue) throws {
        guard case .array(var materials)? = raw["materials"] else { return }
        for i in materials.indices {
            if case .string(let role)? = materials[i]["role"], let renamed = MaterialRole.legacy[role] {
                materials[i]["role"] = .string(renamed.rawValue)
            }
            if materials[i]["examIds"] == nil { materials[i]["examIds"] = .array([]) }
        }
        raw["materials"] = .array(materials)
    }

    /// v3 exams had a kind (midterm, final, quiz, other) the prep folder was named from. The exam now keeps the folder
    /// it had, so its files stay put. An `other` exam had none; it gets one from its title, as a new exam would, after
    /// the others, so it never takes a name a real folder already holds.
    static func dropExamKind(_ raw: inout JSONValue) throws {
        guard case .array(var exams)? = raw["exams"] else { return }
        var quizzes = 0
        var unnamed: [Int] = []
        for i in exams.indices {
            let kind = exams[i]["kind"]
            exams[i]["kind"] = nil
            if kind == .string("quiz") { quizzes += 1 }
            let title = exams[i]["title"].flatMap { if case .string(let t) = $0 { t } else { nil } } ?? ""
            // The v3 rule: a title that is a standard folder name names the folder, else the kind does.
            let named = StandardLayout.isExamFolderName(title)
            let byKind: String? = switch kind {
            case .string("midterm"): StandardLayout.midtermFolder
            case .string("final"): StandardLayout.finalFolder
            case .string("quiz"): StandardLayout.quizFolderPrefix + "\(quizzes)"
            default: nil
            }
            if let folder = named ? title : byKind {
                exams[i]["folder"] = .string(folder)
                if title.isEmpty { exams[i]["title"] = .string(folder) }
            } else {
                unnamed.append(i)
            }
        }
        var taken = Set(exams.compactMap { e in e["folder"].flatMap { if case .string(let f) = $0 { f } else { nil } } })
        for i in unnamed {
            let title = exams[i]["title"].flatMap { if case .string(let t) = $0 { t } else { nil } } ?? ""
            let folder = MaterialIntake.examFolder(title: title, taken: taken)
            taken.insert(folder)
            exams[i]["folder"] = .string(folder)
            if title.isEmpty { exams[i]["title"] = .string(folder) }
        }
        raw["exams"] = .array(exams)
    }

    /// v2 stored each session's place in its week, given as "last + 1" when it was made, so a makeup added first took
    /// 10주차-2 and the class before it 10주차-3. The place now follows the dates in the week.
    static func dropSessionIndex(_ raw: inout JSONValue) throws {
        guard case .array(var sessions)? = raw["sessions"] else { return }
        for i in sessions.indices { sessions[i]["index"] = nil }
        raw["sessions"] = .array(sessions)
    }

    /// v1 sessions had a `kind` and a lab number. A session is now one class: `cancelled` is a flag, a lab is a unit
    /// the session links to, and recitations and makeups are plain sessions.
    static func dropSessionKind(_ raw: inout JSONValue) throws {
        guard case .array(var sessions)? = raw["sessions"] else { return }
        var labs: [(index: Int, number: Int)] = []
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
            // A lab without a number keeps only the units it already links to: guessing one from its place among labs
            // linked a real session to the wrong lab.
            case .string("lab"):
                if case .number(let n)? = number { labs.append((i, Int(n))) }
            default: break
            }
        }
        raw["sessions"] = .array(sessions)
        guard !labs.isEmpty else { return }

        var file = try JSONFormat.decoder.decode(CourseFile.self, from: JSONFormat.encoder.encode(raw))
        // The model has no topic any more; the raw session still holds the one the lab's unit is named after.
        let topic = { (i: Int) -> String in if case .string(let t)? = sessions[i]["topic"] { t } else { "" } }
        // By number, then date, so a lab's unit takes its title from its first session.
        for lab in labs.map({ (session: file.sessions[$0.index], topic: topic($0.index), number: $0.number) })
            .sorted(by: { ($0.number, $0.session.date) < ($1.number, $1.session.date) }) {
            let s = lab.session
            file.linkLab(lab.number, session: s.id, experiment: lab.topic, id: derivedID(s.id), device: s.updatedBy, at: s.updatedAt)
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
