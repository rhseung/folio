import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct FolderProbeTests {
    @Test func theStandardFixtureReadsAsAFolioFolderReadyToOpen() throws {
        let url = try Fixture.standard.copyToTemp()
        guard case .gist(let semesters, let courses) = FolderKind(try FolderProbe.outline(of: url)) else {
            Issue.record("not read as a GIST folder")
            return
        }
        // Credited courses too, a level deeper under `_Credited/<source>`.
        let stores = try GISTStore(url: url).courseStores()
        #expect(stores.contains { $0.url.path().contains(StandardLayout.creditedFolder) })
        #expect(semesters > 0)
        #expect(courses == stores.count)
        #expect(FolderProbe.availability(of: url) == .ready)
    }

    @Test func anEmptyFolderIsEmptyAndAGoneOneMissing() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "folio-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #expect(FolderKind(try FolderProbe.outline(of: url)) == .empty)
        #expect(FolderProbe.availability(of: url) == .ready)
        try FileManager.default.removeItem(at: url)
        #expect(FolderProbe.availability(of: url) == .missing)
    }

    @Test func aCourseFileStillInICloudKeepsTheFolderDownloading() throws {
        let url = try Fixture.standard.copyToTemp()
        let course = try #require(try GISTStore(url: url).courseStores().first).url.appending(path: ".folio")
        try FileManager.default.moveItem(at: course.appending(path: "course.json"), to: course.appending(path: ".course.json.icloud"))
        guard case .downloading(let done, let total) = FolderProbe.availability(of: url) else {
            Issue.record("a placeholder read as here")
            return
        }
        #expect(done == total - 1)
    }

    @Test func theOutlineStopsAtTwoLevels() throws {
        let url = try Fixture.standard.copyToTemp()
        let outline = try FolderProbe.outline(of: url)
        let semester = try #require(outline.children.first { SemesterFolder(name: $0.name) != nil })
        let course = try #require(semester.children.first { StandardLayout.isCourseFolderName($0.name) })
        #expect(course.children.isEmpty)
    }
}
