import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct ImportWriteTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)

    func result(courseFiles: [String: CourseFile]) -> NotionImportResult {
        NotionImportResult(transcript: Transcript(), catalog: Catalog(), courseFiles: courseFiles, warnings: [])
    }

    @Test func neverOverwrites() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let before = try Data(contentsOf: gist.transcriptURL)
        #expect(throws: MoveJournal.Failure.self) { try gist.write(result(courseFiles: [:])) }
        #expect(try Data(contentsOf: gist.transcriptURL) == before)

        try FileManager.default.removeItem(at: gist.transcriptURL)
        let existing = "2026-3/EC4207 그래프 이론"
        let fresh = "2026-3/EC9999 새 과목"
        try FileManager.default.createDirectory(at: gist.url.appending(path: fresh), withIntermediateDirectories: true)
        let file = CourseFile(course: Course(device: device, at: now, title: "새 과목"))
        let skipped = try gist.write(result(courseFiles: [existing: file, fresh: file]))

        #expect(skipped == [existing])
        #expect(try CourseStore(url: gist.url.appending(path: fresh)).load().model.course.title == "새 과목")
        #expect(try CourseStore(url: gist.url.appending(path: existing)).load().model.course.title == "그래프 이론")
        #expect(try gist.loadCatalog().model == Catalog())
    }
}
