@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

/// Synthetic payloads only: the real exports are academic data and never enter the repo.
struct ImportCommandTests {
    let h = Harness()
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "folio-payload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func payload(_ name: String, _ json: String) throws -> String {
        let url = dir.appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
        return url.path
    }

    @Test func notion() throws {
        let fall = UUID(), ec = UUID()
        let path = try payload("export.json", """
            {"semesters": [{"id": "\(fall)", "title": "2026 가을학기", "start": "2026-09-01"}],
             "grades": [], "categories": [], "people": [],
             "codes": [{"id": "\(ec)", "prefix": "EC", "department": "", "program": ""}],
             "courses": [{"id": "\(UUID())", "title": "콜로퀴움", "number": "9331-01", "credits": 0, "mode": "S/U",
                          "semesterId": "\(fall)", "codeIds": ["\(ec)"]}]}
            """)
        // The fixture already has transcript.json, which the import must never overwrite.
        let (a, b) = (try Harness.fixtureCopy(), try Harness.fixtureCopy())
        #expect(h.cli(["import", "notion", path], gist: a).code == Exit.rule.rawValue)
        for gist in [a, b] { try FileManager.default.removeItem(at: GISTStore(url: gist).transcriptURL) }
        let r = h.cli(["import", "notion", path], gist: a)
        #expect(r.code == 0, "\(r.err)")
        try h.direct(ImportNotion(export: try ImportCommand.read(NotionExport.self, path)), gist: b)
        try expectSameFiles(a, b)
    }

    @Test func notes() throws {
        let note = UUID()
        _ = try payload("dump/\(Harness.graphTheory)/notes/a.md", "본문")
        _ = try payload("dump/\(Harness.graphTheory)/index.json", """
            {"coursePageId": "\(Harness.graphTheory)", "title": "그래프 이론", "images": [], "scores": [],
             "notes": [{"id": "\(note)", "title": "7주차-2", "kind": "러프", "date": "2026-10-14", "file": "notes/a.md"}]}
            """)
        let folder = dir.appending(path: "dump").path
        try h.expectSame(["import", "notes", folder]) { _ in ImportNotes(folder: folder) }
        let r = h.cli(["import", "notes", folder, "--dry-run"], gist: try Harness.fixtureCopy())
        #expect(r.out.contains("노트 +1") && r.out.contains("Notes/7주차-2.md"), "\(r.out)")
    }

    @Test func calendar() throws {
        let path = try payload("meetings.json", """
            [{"course": "EC4207 그래프 이론", "start": "2026-10-26T01:00:00Z", "end": "2026-10-26T02:15:00Z",
              "room": "A229", "topic": "트리"}]
            """)
        try h.expectSame(["import", "calendar", path]) { _ in
            ImportCalendar(meetings: try ImportCommand.read([CalendarMeeting].self, path, iso8601: true))
        }
        let r = h.cli(["import", "calendar", path, "--dry-run"], gist: try Harness.fixtureCopy())
        #expect(r.out.contains("회차 +1"), "\(r.out)")
    }

    @Test func exams() throws {
        let path = try payload("exams.json", """
            [{"course": "EC4207 그래프 이론", "kind": "midterm", "start": "2026-10-20T11:00:00Z", "end": "2026-10-20T13:45:00Z",
              "location": "C104", "memo": ""},
             {"course": "XX0000 없음", "kind": "final", "start": "2026-12-16T00:00:00Z", "end": "2026-12-16T02:00:00Z",
              "location": "", "memo": ""}]
            """)
        try h.expectSame(["import", "exams", path]) { _ in
            ImportExams(exams: try ImportCommand.read([CalendarExam].self, path, iso8601: true))
        }
    }

    @Test func units() throws {
        let path = try payload("units.json", #"{"course": "EC4207 그래프 이론", "units": [{"title": "트리", "children": [{"title": "신장 트리"}]}]}"#)
        try h.expectSame(["import", "units", path]) { _ in ImportUnits(files: [try ImportCommand.read(UnitFile.self, path)]) }
    }

    static let requirements = #"{"admissionYear": 2023, "categories": [{"name": "전공선택", "group": "전공", "isMajor": true}]}"#

    @Test func requirements() throws {
        let path = try payload("requirements.json", Self.requirements)
        try h.expectSame(["import", "requirements", path]) { _ in
            ImportRequirements(file: try ImportCommand.read(RequirementFile.self, path))
        }
    }

    @Test func handbook() throws {
        let req = try payload("requirements.json", Self.requirements)
        let path = try payload("handbook.json", #"{"year": 2023, "source": "2023 학사편람", "areas": {"EC4207": "전공선택"}}"#)
        try h.expectSame(["import", "handbook", path, "--accept"], setup: [["import", "requirements", req]]) { _ in
            ImportHandbook(handbook: try ImportCommand.read(Handbook.self, path), accept: true)
        }
        let unknown = try payload("unknown.json", #"{"year": 2023, "source": "", "areas": {"EC4207": "없는 분류"}}"#)
        #expect(h.cli(["import", "handbook", unknown], gist: try Harness.fixtureCopy()).code == Exit.rule.rawValue)
    }

    @Test func dryRunWritesNothing() throws {
        let path = try payload("units.json", #"{"course": "EC4207 그래프 이론", "units": [{"title": "트리"}]}"#)
        let gist = try Harness.fixtureCopy()
        let before = try Harness.files(gist)
        let r = h.cli(["import", "units", path, "--dry-run"], gist: gist)
        #expect(r.code == 0 && r.out.contains("단원 +1"))
        #expect(try Harness.files(gist) == before)
    }

    @Test func checkExitsFourOnIssues() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["check"], gist: gist).code == 0)
        try Data().write(to: gist.appending(path: "stray.txt"))
        #expect(h.cli(["check", "--json"], gist: gist).code == Exit.rule.rawValue)
    }

    func expectSameFiles(_ a: URL, _ b: URL, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let (fa, fb) = (try Harness.files(a), try Harness.files(b))
        #expect(fa.keys.sorted() == fb.keys.sorted(), sourceLocation: sourceLocation)
        for (path, data) in fa where Harness.canonical(fb[path]) != Harness.canonical(data) {
            Issue.record("\(path) differs", sourceLocation: sourceLocation)
        }
    }
}
