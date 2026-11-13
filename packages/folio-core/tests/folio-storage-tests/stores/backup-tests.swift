import FolioDomain
import FolioFixtures
@testable import FolioStorage
import Foundation
import Testing

struct BackupTests {
    let calendar = Calendar(identifier: .iso8601)
    let today = LocalDate("2026-10-23")!

    func files(under root: URL) -> Set<String> {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path.count + 1
        let walk = FileManager.default.enumerator(at: root.standardizedFileURL.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey])
        return Set((walk?.allObjects as? [URL] ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { String($0.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(base)) })
    }

    @Test func clonesTheWholeGISTOnTheSameVolumeAndRestoresOneCourse() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let folder = gist.url.deletingLastPathComponent().appending(path: "backups")
        let store = BackupStore(gist: gist, folder: folder)
        #expect(store.clones)
        let created = try store.backUp(today: today, dailyDays: 30, calendar: calendar)
        #expect(created.url.lastPathComponent == "Folio-2026-10-23")
        #expect(created.skipped == 0)
        #expect(files(under: created.url) == files(under: gist.url))
        #expect(store.archives().map(\.day) == [today])
        #expect(store.archives()[0].isClone)

        let course = try #require(try gist.courseStores().first)
        let target = folder.deletingLastPathComponent().appending(path: "restored")
        try store.restore(course: course, from: store.archives()[0], to: target)
        #expect(files(under: target) == files(under: course.url))
        #expect(throws: BackupStore.Failure.self) { try store.restore(course: course, from: store.archives()[0], to: target) }
    }

    @Test func keepsTheBytesOfAnNFCName() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let nfc = "류현승.txt".precomposedStringWithCanonicalMapping
        let fd = open(gist.url.path(percentEncoded: false) + "/" + nfc, O_CREAT | O_WRONLY, 0o644)
        #expect(fd >= 0)
        close(fd)
        let store = BackupStore(gist: gist, folder: gist.url.deletingLastPathComponent().appending(path: "backups"))
        let created = try store.backUp(today: today, dailyDays: 30, calendar: calendar)
        let names = try FileManager.default.contentsOfDirectory(atPath: created.url.path(percentEncoded: false))
        #expect(names.contains { Array($0.utf8) == Array(nfc.utf8) })
    }

    @Test func skipsFilesOnlyInICloud() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        var store = BackupStore(gist: gist, folder: gist.url.deletingLastPathComponent().appending(path: "backups"))
        store.isEvicted = { $0.hasSuffix(".pdf") }
        let pdfs = files(under: gist.url).filter { $0.hasSuffix(".pdf") }
        #expect(!pdfs.isEmpty)
        let created = try store.backUp(today: today, dailyDays: 30, calendar: calendar)
        #expect(created.skipped == pdfs.count)
        #expect(files(under: created.url) == files(under: gist.url).subtracting(pdfs))
    }

    @Test func zipsNotesAndMetadataOnlyOffTheVolumeAndRestoresOneCourse() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let folder = gist.url.deletingLastPathComponent().appending(path: "backups")
        let store = BackupStore(gist: gist, folder: folder)
        let created = try store.backUp(today: today, dailyDays: 30, calendar: calendar, clone: false)
        #expect(created.url.lastPathComponent == "Folio-2026-10-23.zip")
        #expect(store.archives().map(\.day) == [today])
        #expect(!store.archives()[0].isClone)

        let course = try #require(try gist.courseStores().first)
        let target = folder.deletingLastPathComponent().appending(path: "restored")
        try store.restore(course: course, from: store.archives()[0], to: target)
        let restored = Set(try FileManager.default.contentsOfDirectory(atPath: target.path))
        #expect(restored.contains(StandardLayout.metadataFolder))
        #expect(restored.isSubset(of: [CourseFolder.notes.rawValue, CourseFolder.ink.rawValue, StandardLayout.metadataFolder]))
    }

    @Test func prunesByRetentionAndRefusesFolderInsideGIST() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let folder = gist.url.deletingLastPathComponent().appending(path: "backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for day in ["2026-08-10", "2026-08-11"] {
            FileManager.default.createFile(atPath: folder.appending(path: "Folio-\(day).zip").path, contents: Data())
        }
        try FileManager.default.createDirectory(at: folder.appending(path: "Folio-2026-10-20"), withIntermediateDirectories: false)
        let store = BackupStore(gist: gist, folder: folder)
        try store.backUp(today: today, dailyDays: 30, calendar: calendar)
        #expect(store.archives().map(\.day.description) == ["2026-10-23", "2026-10-20", "2026-08-11"])

        let inside = BackupStore(gist: gist, folder: gist.url.appending(path: "backups"))
        #expect(throws: BackupStore.Failure.self) { try inside.backUp(today: today, dailyDays: 30, calendar: calendar) }
    }
}
