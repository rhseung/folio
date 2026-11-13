import FolioDomain
@testable import FolioStorage
import Foundation
import Testing

/// course.json v5 -> v6: a note's session moves to the session's pointer, and only topic notes keep units.
struct NoteLinkMigrationTests {
    let unit = UUID()

    func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "A0000000-0000-4000-8000-%012d", n))! }
    func session(_ n: Int, rough: Int? = nil, review: Int? = nil, draft: Bool = false) -> JSONValue {
        var fields: [String: JSONValue] = ["id": .string(id(n).uuidString), "futureSessionField": .string("keep me")]
        if let rough { fields["roughNoteId"] = .string(id(rough).uuidString) }
        if let review { fields["reviewNoteId"] = .string(id(review).uuidString) }
        if draft { fields["reviewNoteDraft"] = .bool(true) }
        return .object(fields)
    }
    func note(_ n: Int, _ kind: String, session: Int? = nil) -> JSONValue {
        var fields: [String: JSONValue] = ["id": .string(id(n).uuidString), "kind": .string(kind), "unitIds": .array([.string(unit.uuidString)])]
        if let session { fields["sessionId"] = .string(id(session).uuidString) }
        return .object(fields)
    }
    func migrated(sessions: [JSONValue], notes: [JSONValue]) throws -> (sessions: [JSONValue], notes: [JSONValue]) {
        var raw: JSONValue = .object(["sessions": .array(sessions), "notes": .array(notes)])
        try CourseFile.keepNoteLinksOnSessions(&raw)
        guard case .array(let s)? = raw["sessions"], case .array(let n)? = raw["notes"] else { throw CancellationError() }
        return (s, n)
    }

    @Test func aNotesSessionMovesToTheSessionsFreeSlot() throws {
        let r = try migrated(sessions: [session(1), session(2, review: 21)], notes: [note(10, "rough", session: 1), note(11, "review", session: 2), note(21, "review", session: 2)])

        // Session 2's review slot was taken by note 21, so note 11 comes out without a session rather than as a second one.
        #expect(r.sessions[0]["roughNoteId"] == .string(id(10).uuidString))
        #expect(r.sessions[1]["reviewNoteId"] == .string(id(21).uuidString))
        #expect(r.notes.allSatisfy { $0["sessionId"] == nil })
        #expect(r.sessions[0]["futureSessionField"] == .string("keep me"))
    }

    /// `import calendar` made a session point at a free note; the note becomes that session's review note.
    @Test func aPointedNoteTakesItsSlotsKind() throws {
        let r = try migrated(sessions: [session(1, review: 10)], notes: [note(10, "free")])
        #expect(r.notes[0]["kind"] == .string("review"))
    }

    /// The first pointer in the file keeps a note two slots claimed; the other lets go, with its draft mark.
    @Test func aSecondPointerAtANoteLetsGo() throws {
        let r = try migrated(sessions: [session(1, review: 10), session(2, review: 10, draft: true), session(3, rough: 10)], notes: [note(10, "review")])
        #expect(r.sessions[0]["reviewNoteId"] == .string(id(10).uuidString))
        #expect(r.sessions[1]["reviewNoteId"] == nil && r.sessions[1]["reviewNoteDraft"] == nil)
        #expect(r.sessions[2]["roughNoteId"] == nil)
    }

    /// `import calendar` once took any unlinked note named after a class, a topic note too; it stays a topic note
    /// with its units, and the session lets go of it.
    @Test func aPointedTopicOrExamNoteKeepsItsKind() throws {
        let r = try migrated(sessions: [session(1, review: 10, draft: true), session(2, rough: 11)], notes: [note(10, "topic"), note(11, "exam_summary")])
        #expect(r.notes.map { $0["kind"] } == [.string("topic"), .string("exam_summary")])
        #expect(r.notes[0]["unitIds"] == .array([.string(unit.uuidString)]))
        #expect(r.sessions[0]["reviewNoteId"] == nil && r.sessions[0]["reviewNoteDraft"] == nil && r.sessions[1]["roughNoteId"] == nil)
    }

    @Test func onlyTopicNotesKeepUnits() throws {
        let r = try migrated(sessions: [], notes: [note(10, "topic"), note(11, "review"), note(12, "exam_summary"), note(13, "free")])
        #expect(r.notes.map { $0["unitIds"] } == [.array([.string(unit.uuidString)]), .array([]), .array([]), .array([])])
    }

    /// The whole chain on a real v5 file: it reads as v6 and passes the model's note rules.
    @Test func aV5FileReadsWithItsLinksOnTheSession() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let course = Course(device: UUID(), at: .now, title: "그래프 이론")
        var s = Session(device: UUID(), at: .now, week: 1, date: .now)
        let note = UUID()
        s.unitIds = []
        var file = CourseFile(course: course, sessions: [s])
        file.notes = [NoteEntry(id: note, device: UUID(), at: .now, path: "Notes/1주차-1.md", meta: NoteMeta(id: note, kind: .rough))]
        var raw = try JSONFormat.decoder.decode(JSONValue.self, from: JSONFormat.encoder.encode(file))
        raw["schemaVersion"] = .number(5)
        guard case .array(var notes)? = raw["notes"] else { Issue.record("no notes"); return }
        notes[0]["sessionId"] = .string(s.id.uuidString)
        notes[0]["unitIds"] = .array([.string(unit.uuidString)])
        raw["notes"] = .array(notes)
        let url = folder.appending(path: "course.json")
        try JSONFormat.encoder.encode(raw).write(to: url)

        let doc = try StoredDocument<CourseFile>.read(from: url)
        #expect(doc.model.sessions[0].roughNoteId == note)
        #expect(doc.model.notes[0].unitIds.isEmpty)
        #expect(doc.model.meta(of: doc.model.notes[0]).sessionId == s.id)
        try doc.write(to: url)
        let written = try JSONFormat.decoder.decode(JSONValue.self, from: Data(contentsOf: url))
        guard case .array(let saved)? = written["notes"] else { Issue.record("no notes"); return }
        #expect(saved[0]["sessionId"] == nil && written["schemaVersion"] == .number(Double(CourseFile.schemaVersion)))
    }
}
