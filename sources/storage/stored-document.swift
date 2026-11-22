import FolioCore
import FolioDomain
import Foundation

extension Transcript: StoredModel {
    public static let schemaVersion = 2
    public static let migrations: [Int: @Sendable (inout JSONValue) throws -> Void] = [1: unfileCourses]

    static func unfileCourses(_ raw: inout JSONValue) throws {
        let courses = raw["courses"]
        raw["courses"] = nil
        if case .array(let items)? = courses, !items.isEmpty { raw["unfiledCourses"] = .array(items) }
    }
}

extension CourseFile: StoredModel {
    public static let schemaVersion = 8
    public static let migrations: [Int: @Sendable (inout JSONValue) throws -> Void] = [
        1: dropSessionKind, 2: dropSessionIndex, 3: dropExamKind, 4: splitRolesByOrigin, 5: keepNoteLinksOnSessions, 6: spellOutRepeats,
        7: keepOnlyEditedLinks,
    ]

    // 회차의 단원과 시험 범위를 저장하지 않고 계산하게 되면서, 저장된 연결을 계산값과 비교해 차이만 남긴다. 계산값에
    // 없는 단원은 더한 단원, 계산값에만 있는 단원은 뺀 단원이 되므로 화면에 보이는 연결은 그대로다. 단원 쪽의 짝
    // (`sessionIds`, `examIds`)도 함께 읽는다. 짝 규칙이 생기기 전 파일에는 한쪽에만 적힌 연결이 있다.
    static func keepOnlyEditedLinks(_ raw: inout JSONValue) throws {
        func ids(_ value: JSONValue?) -> [UUID] {
            guard case .array(let items)? = value else { return [] }
            return items.compactMap { if case .string(let s) = $0 { UUID(uuidString: s) } else { nil } }
        }
        func id(_ value: JSONValue?) -> UUID? { if case .string(let s)? = value { UUID(uuidString: s) } else { nil } }
        var sessions: [JSONValue] = if case .array(let a)? = raw["sessions"] { a } else { [] }
        var units: [JSONValue] = if case .array(let a)? = raw["units"] { a } else { [] }
        var exams: [JSONValue] = if case .array(let a)? = raw["exams"] { a } else { [] }

        var sessionUnits: [UUID: Set<UUID>] = [:]
        var examUnits: [UUID: Set<UUID>] = [:]
        for s in sessions { if let sid = id(s["id"]) { sessionUnits[sid, default: []].formUnion(ids(s["unitIds"])) } }
        for e in exams { if let eid = id(e["id"]) { examUnits[eid, default: []].formUnion(ids(e["scopeUnitIds"])) } }
        for u in units {
            guard let uid = id(u["id"]) else { continue }
            for sid in ids(u["sessionIds"]) { sessionUnits[sid, default: []].insert(uid) }
            for eid in ids(u["examIds"]) { examUnits[eid, default: []].insert(uid) }
        }
        for i in sessions.indices { sessions[i]["unitIds"] = nil }
        for i in units.indices {
            units[i]["sessionIds"] = nil
            units[i]["examIds"] = nil
        }
        for i in exams.indices { exams[i]["scopeUnitIds"] = nil }
        if raw["sessions"] != nil { raw["sessions"] = .array(sessions) }
        if raw["units"] != nil { raw["units"] = .array(units) }
        if raw["exams"] != nil { raw["exams"] = .array(exams) }

        var file = try JSONFormat.decoder.decode(CourseFile.self, from: JSONFormat.encoder.encode(raw))
        // 시험 범위의 계산값은 회차의 단원을 읽으므로 회차를 먼저 맞춘다. 앞 마이그레이션(`dropSessionKind`)이 이
        // 모양으로 이미 더한 실험 단원도 지킨다.
        for s in file.sessions { file.setUnits(Array(sessionUnits[s.id, default: []].union(s.addedUnitIds)), session: s.id) }
        for e in file.exams { file.setScope(Array(examUnits[e.id, default: []].union(e.addedScopeUnitIds)), exam: e.id) }
        let encoded = try JSONFormat.decoder.decode(JSONValue.self, from: JSONFormat.encoder.encode(file))
        raw = JSONValue.preservingUnknownKeys(old: raw, new: encoded, model: file)
    }

    static func spellOutRepeats(_ raw: inout JSONValue) throws {
        guard case .array(var assignments)? = raw["assignments"] else { return }
        for i in assignments.indices {
            guard case .string(let text)? = assignments[i]["repeats"] else { continue }
            assignments[i]["repeats"] =
                AssignmentRepeat(text: text).map { r in
                    .object([
                        "every": .number(Double(r.every)), "unit": .string(r.unit.rawValue),
                        "weekdays": .array(r.weekdays.map { .number(Double($0)) }),
                    ])
                } ?? nil
        }
        raw["assignments"] = .array(assignments)
    }

    static func keepNoteLinksOnSessions(_ raw: inout JSONValue) throws {
        func id(_ value: JSONValue?) -> UUID? { if case .string(let s)? = value { UUID(uuidString: s) } else { nil } }
        let slots = [("roughNoteId", "rough"), ("reviewNoteId", "review")]
        var sessions: [JSONValue] = if case .array(let a)? = raw["sessions"] { a } else { [] }
        var notes: [JSONValue] = if case .array(let a)? = raw["notes"] { a } else { [] }
        var kindOf: [UUID: String] = [:]
        let kept: Set<String> = [NoteKind.unit.rawValue, NoteKind.examSummary.rawValue]
        let ownUnits = Set(
            notes.compactMap { n -> UUID? in
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
                let s = sessions.firstIndex(where: { id($0["id"]) == session }), id(sessions[s][key]) == nil
            else { continue }
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

    static func dropExamKind(_ raw: inout JSONValue) throws {
        guard case .array(var exams)? = raw["exams"] else { return }
        var quizzes = 0
        var unnamed: [Int] = []
        for i in exams.indices {
            let kind = exams[i]["kind"]
            exams[i]["kind"] = nil
            if kind == .string("quiz") { quizzes += 1 }
            let title = exams[i]["title"].flatMap { if case .string(let t) = $0 { t } else { nil } } ?? ""
            let named = StandardLayout.isExamFolderName(title)
            let byKind: String? =
                switch kind {
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

    static func dropSessionIndex(_ raw: inout JSONValue) throws {
        guard case .array(var sessions)? = raw["sessions"] else { return }
        for i in sessions.indices { sessions[i]["index"] = nil }
        raw["sessions"] = .array(sessions)
    }

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
            case .string("recitation"):
                if sessions[i]["topic"] == .string("") { sessions[i]["topic"] = .string("리시테이션") }
            // 번호 없는 실험은 이미 연결한 단원만 지킨다. 실험들 사이의 순서로 번호를 짐작했더니 실제 회차가 엉뚱한 실험에
            // 연결되었다.
            case .string("lab"):
                if case .number(let n)? = number { labs.append((i, Int(n))) }
            default: break
            }
        }
        raw["sessions"] = .array(sessions)
        guard !labs.isEmpty else { return }

        var file = try JSONFormat.decoder.decode(CourseFile.self, from: JSONFormat.encoder.encode(raw))
        let topic = { (i: Int) -> String in if case .string(let t)? = sessions[i]["topic"] { t } else { "" } }
        for lab in labs.map({ (session: file.sessions[$0.index], topic: topic($0.index), number: $0.number) })
            .sorted(by: { ($0.number, $0.session.date) < ($1.number, $1.session.date) })
        {
            let s = lab.session
            file.linkLab(lab.number, session: s.id, experiment: lab.topic, id: derivedID(s.id), device: s.updatedBy, at: s.updatedAt)
        }
        let encoded = try JSONFormat.decoder.decode(JSONValue.self, from: JSONFormat.encoder.encode(file))
        raw = JSONValue.preservingUnknownKeys(old: raw, new: encoded, model: file)
    }

    // 저장하기 전에 v1 파일을 다시 읽어도 같은 단원이 나와야 하므로, id를 첫 실험 회차의 id에서 만든다.
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
    public static let schemaVersion = 2
    public static let migrations: [Int: @Sendable (inout JSONValue) throws -> Void] = [1: groupNotifications]

    // 알림 종류마다 따로 있던 켜기와 시각 칸(`examMorning`, `examMorningMinute`)을 종류 하나의 객체로 모은다. 예전 칸 이름은 이
    // 마이그레이션이 읽는 파일 형식이라 종류 이름에서 만들지 않고 그대로 적는다.
    static func groupNotifications(_ raw: inout JSONValue) throws {
        guard case .object(var old)? = raw["notifications"] else { return }
        let moves = [
            ("assignmentDue", "assignmentDue", "on"), ("assignmentLeadHours", "assignmentDue", "leadHours"),
            ("examDayBefore", "examDayBefore", "on"), ("examDayBeforeMinute", "examDayBefore", "minute"),
            ("examMorning", "examMorning", "on"), ("examMorningMinute", "examMorning", "minute"),
            ("dailyReview", "dailyReview", "on"), ("dailyReviewMinute", "dailyReview", "minute"),
            ("attendance", "attendance", "on"),
        ]
        var grouped: [String: [String: JSONValue]] = [:]
        for (from, kind, field) in moves {
            if let value = old.removeValue(forKey: from) { grouped[kind, default: [:]][field] = value }
        }
        for (kind, fields) in grouped { old[kind] = .object(fields) }
        raw["notifications"] = .object(old)
    }
}

extension QuizFile: StoredModel {
    public static let schemaVersion = 1
}

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
