import FolioDomain
@testable import FolioStorage
import Foundation
import Testing

struct StoredDocumentTests {
    let dir = FileManager.default.temporaryDirectory.appending(path: "folio-\(UUID().uuidString)")
    var url: URL { dir.appending(path: "course.json") }

    func writeRaw(_ json: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    func readRaw() throws -> JSONValue {
        try JSONFormat.decoder.decode(JSONValue.self, from: Data(contentsOf: url))
    }

    let courseJSON = """
    {
      "schemaVersion": 1,
      "futureTopLevel": {"a": 1},
      "course": {
        "id": "C0000000-0000-4000-8000-000000000001",
        "createdAt": "2026-08-25T09:00:00.000Z", "updatedAt": "2026-08-25T09:00:00.000Z",
        "updatedBy": "D0000000-0000-4000-8000-000000000001",
        "title": "그래프 이론", "titleEn": "", "codes": [], "number": "", "categoryIds": [], "instructorIds": [],
        "credits": 3, "gradingMode": "relative", "schedule": [], "color": "", "folderRoles": {}, "memo": "",
        "absoluteScore": 91.5,
        "futureCourseField": "keep me"
      },
      "materials": [
        {
          "id": "A0000000-0000-4000-8000-000000000001",
          "createdAt": "2026-08-25T09:00:00.000Z", "updatedAt": "2026-08-25T09:00:00.000Z",
          "updatedBy": "D0000000-0000-4000-8000-000000000001",
          "path": "Lectures/01_Intro.pdf", "isFolder": false, "sessionIds": [], "unitIds": [], "status": "classified",
          "futureMaterialField": [1, 2]
        }
      ]
    }
    """

    @Test func preservesUnknownKeysAndDropsClearedOnes() throws {
        try writeRaw(courseJSON)
        var doc = try StoredDocument<CourseFile>.read(from: url)
        #expect(doc.model.course.absoluteScore == 91.5)

        doc.model.course.title = "Graph Theory"
        doc.model.course.absoluteScore = nil
        try doc.write(to: url)

        let raw = try readRaw()
        #expect(raw["futureTopLevel"] == .object(["a": .number(1)]))
        #expect(raw["course"]?["futureCourseField"] == .string("keep me"))
        #expect(raw["course"]?["title"] == .string("Graph Theory"))
        #expect(raw["course"]?["absoluteScore"] == nil)
        guard case .array(let materials)? = raw["materials"] else { Issue.record("no materials"); return }
        #expect(materials.first?["futureMaterialField"] == .array([.number(1), .number(2)]))
    }

    @Test func removedArrayElementsStayRemoved() throws {
        try writeRaw(courseJSON)
        var doc = try StoredDocument<CourseFile>.read(from: url)
        doc.model.materials = []
        try doc.write(to: url)
        #expect(try readRaw()["materials"] == .array([]))
    }

    @Test func writingIsStable() throws {
        try writeRaw(courseJSON)
        try StoredDocument<CourseFile>.read(from: url).write(to: url)
        let first = try Data(contentsOf: url)
        try StoredDocument<CourseFile>.read(from: url).write(to: url)
        #expect(try Data(contentsOf: url) == first)
    }

    @Test func newerSchemaIsReadOnly() throws {
        try writeRaw(courseJSON.replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 99"))
        let doc = try StoredDocument<CourseFile>.read(from: url)
        #expect(doc.isReadOnly)
        #expect(throws: StorageError.self) { try doc.write(to: url) }
    }

    @Test func missingVersionIsRejected() throws {
        try writeRaw(#"{"semesters": []}"#)
        #expect(throws: StorageError.self) { try StoredDocument<Transcript>.read(from: url) }
    }

    struct Renamed: StoredModel, Equatable {
        static let schemaVersion = 2
        static let migrations: [Int: @Sendable (inout JSONValue) throws -> Void] = [
            1: { raw in
                raw["name"] = raw["title"]
                raw["title"] = nil
            },
        ]
        var name: String
    }

    @Test func migratesOldVersions() throws {
        try writeRaw(#"{"schemaVersion": 1, "title": "x"}"#)
        let doc = try StoredDocument<Renamed>.read(from: url)
        #expect(doc.model == Renamed(name: "x"))
        try doc.write(to: url)
        #expect(try readRaw() == .object(["schemaVersion": .number(2), "name": .string("x")]))
    }

    @Test func newDocumentRoundTrips() throws {
        let device = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000.123)
        let semester = Semester(device: device, at: now, year: 2026, term: .fall, start: LocalDate("2026-09-01"))
        try StoredDocument(new: Transcript(semesters: [semester])).write(to: url)
        #expect(try StoredDocument<Transcript>.read(from: url).model.semesters == [semester])
    }
}
