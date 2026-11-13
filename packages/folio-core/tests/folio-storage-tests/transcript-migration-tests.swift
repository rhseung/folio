import FolioDomain
import Foundation
import Testing

@testable import FolioStorage

struct TranscriptMigrationTests {
    func write(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "transcript-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    let course =
        #"{"id":"C0000000-0000-4000-8000-0000000000AA","createdAt":"2026-02-20T09:00:00.000Z","updatedAt":"2026-02-20T09:00:00.000Z","updatedBy":"D0000000-0000-4000-8000-000000000001","title":"콜로퀴움","codes":[],"number":"9331","categoryIds":[],"instructorIds":[],"credits":1,"gradingMode":"pass_fail","schedule":[],"color":"","folderRoles":{},"memo":"","titleEn":""}"#

    /// v1's folderless courses wait under `unfiledCourses`, and keep what this version doesn't read.
    @Test func v1CoursesBecomeUnfiled() throws {
        let url = try write(#"{"schemaVersion":1,"semesters":[],"courses":[\#(course)],"kept":true}"#)
        let doc = try StoredDocument<Transcript>.read(from: url)
        #expect(doc.fileVersion == 1)
        #expect(doc.model.unfiledCourses.map(\.title) == ["콜로퀴움"])
        try doc.write(to: url)
        guard case .object(let raw) = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)) else { Issue.record(); return }
        #expect(raw["schemaVersion"] == .number(2))
        #expect(raw["courses"] == nil)
        #expect(raw["kept"] == .bool(true))
        if case .array(let unfiled)? = raw["unfiledCourses"] { #expect(unfiled.count == 1) } else { Issue.record("unfiledCourses missing") }
    }

    /// Once they are moved, the key leaves the file.
    @Test func emptyUnfiledLeavesNoKey() throws {
        let url = try write(#"{"schemaVersion":1,"semesters":[],"courses":[\#(course)]}"#)
        var doc = try StoredDocument<Transcript>.read(from: url)
        doc.model.unfiledCourses = []
        try doc.write(to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("unfiledCourses") && !text.contains("\"courses\""))
        let empty = try write(#"{"schemaVersion":1,"semesters":[],"courses":[]}"#)
        try StoredDocument<Transcript>.read(from: empty).write(to: empty)
        #expect(!(try String(contentsOf: empty, encoding: .utf8)).contains("ourses"))
    }
}
