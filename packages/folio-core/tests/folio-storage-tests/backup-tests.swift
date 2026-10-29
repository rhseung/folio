import FolioDomain
import FolioFixtures
@testable import FolioStorage
import Foundation
import Testing

struct BackupTests {
    let calendar = Calendar(identifier: .iso8601)

    @Test func archivesNotesAndMetadataOnlyAndRestoresOneCourse() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let folder = gist.url.deletingLastPathComponent().appending(path: "backups")
        let store = BackupStore(gist: gist, folder: folder)
        let today = LocalDate("2026-10-23")!
        let archive = try store.backUp(today: today, dailyDays: 30, calendar: calendar)
        #expect(archive.lastPathComponent == "Folio-2026-10-23.zip")
        #expect(store.archives().map(\.day) == [today])

        let course = try #require(try gist.courseStores().first)
        let target = folder.deletingLastPathComponent().appending(path: "restored")
        try store.restore(course: course, from: store.archives()[0], to: target)
        let restored = Set(try FileManager.default.contentsOfDirectory(atPath: target.path))
        #expect(restored.contains(StandardLayout.metadataFolder))
        #expect(restored.isSubset(of: [CourseFolder.notes.rawValue, CourseFolder.ink.rawValue, StandardLayout.metadataFolder]))
        #expect(throws: BackupStore.Failure.self) { try store.restore(course: course, from: store.archives()[0], to: target) }
    }

    @Test func prunesByRetentionAndRefusesFolderInsideGIST() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let folder = gist.url.deletingLastPathComponent().appending(path: "backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for day in ["2026-08-10", "2026-08-11", "2026-10-20"] {
            FileManager.default.createFile(atPath: folder.appending(path: "Folio-\(day).zip").path, contents: Data())
        }
        let store = BackupStore(gist: gist, folder: folder)
        try store.backUp(today: LocalDate("2026-10-23")!, dailyDays: 30, calendar: calendar)
        #expect(store.archives().map(\.day.description) == ["2026-10-23", "2026-10-20", "2026-08-11"])

        let inside = BackupStore(gist: gist, folder: gist.url.appending(path: "backups"))
        #expect(throws: BackupStore.Failure.self) { try inside.backUp(today: LocalDate("2026-10-23")!, dailyDays: 30, calendar: calendar) }
    }
}
