import FolioDomain
import Foundation
import Testing

struct MaterialTrackingTests {
    let device = UUID()
    let t0 = Date(timeIntervalSince1970: 0)
    let t1 = Date(timeIntervalSince1970: 100)

    func io(hashes: [String: String] = [:], bookmarks: [UUID: String] = [:]) -> TrackingIO {
        TrackingIO(
            resolveBookmark: { bookmarks[$0.id] },
            hash: { hashes[$0] },
            makeBookmark: { Data($0.utf8) }
        )
    }

    func material(_ path: String, hash: String? = nil, size: Int64 = 1) -> Material {
        Material(device: device, at: t0, path: path, hash: hash, size: size, role: MaterialRole(path: path), status: .classified)
    }

    @Test func registersNewFilesByFolderRole() throws {
        let scanned = [
            ScannedEntry(path: "Lectures/05_Matchings.pdf", size: 10),
            ScannedEntry(path: "Syllabus.pdf", size: 20),
            ScannedEntry(path: "Assignments/Project01/robot", isFolder: true),
        ]
        let result = try MaterialTracking.reconcile([], with: scanned, io: io(hashes: ["Lectures/05_Matchings.pdf": "h1"]), device: device, now: t1)

        let lecture = try #require(result.first { $0.path == "Lectures/05_Matchings.pdf" })
        #expect(lecture.role == .lecture && lecture.status == .classified && lecture.hash == "h1" && lecture.createdAt == t1)
        let stray = try #require(result.first { $0.path == "Syllabus.pdf" })
        #expect(stray.role == nil && stray.status == .unclassified)
        let project = try #require(result.first { $0.isFolder })
        #expect(project.role == .assignment && project.hash == nil)
    }

    @Test func unchangedFilesAreNotTouched() throws {
        let m = material("Lectures/01_Intro.pdf", hash: "h")
        let result = try MaterialTracking.reconcile([m], with: [.init(path: m.path, size: 1)], io: io(), device: device, now: t1)
        #expect(result == [m])
    }

    @Test func followsBookmarkAndAdoptsNewFolderRole() throws {
        let m = material("Syllabus.pdf")
        let result = try MaterialTracking.reconcile(
            [m], with: [.init(path: "Lectures/01_Intro.pdf", size: 1)],
            io: io(bookmarks: [m.id: "Lectures/01_Intro.pdf"]), device: device, now: t1
        )
        #expect(result.count == 1)
        #expect(result[0].id == m.id && result[0].path == "Lectures/01_Intro.pdf" && result[0].role == .lecture)
        #expect(result[0].updatedAt == t1 && result[0].updatedBy == device)
    }

    @Test func fallsBackToContentHash() throws {
        let m = material("Lectures/old.pdf", hash: "same", size: 5)
        let scanned: [ScannedEntry] = [.init(path: "Lectures/a.pdf", size: 5), .init(path: "Lectures/b.pdf", size: 5)]
        let result = try MaterialTracking.reconcile(
            [m], with: scanned, io: io(hashes: ["Lectures/a.pdf": "other", "Lectures/b.pdf": "same"]), device: device, now: t1
        )
        #expect(result.first { $0.id == m.id }?.path == "Lectures/b.pdf")
        #expect(result.count == 2)  // a.pdf registered as new
    }

    @Test func missingKeepsLinksAndRecovers() throws {
        var m = material("Lectures/01_Intro.pdf", hash: "h")
        m.unitIds = [UUID()]
        let gone = try MaterialTracking.reconcile([m], with: [], io: io(), device: device, now: t1)
        #expect(gone[0].status == .missing && gone[0].unitIds == m.unitIds)

        let back = try MaterialTracking.reconcile(gone, with: [.init(path: m.path, size: 1)], io: io(), device: device, now: t1)
        #expect(back[0].status == .classified)
    }

    @Test func replacedInPlaceRehashes() throws {
        let m = material("Lectures/01_Intro.pdf", hash: "old", size: 1)
        let result = try MaterialTracking.reconcile(
            [m], with: [.init(path: m.path, size: 2)], io: io(hashes: [m.path: "new"]), device: device, now: t1
        )
        #expect(result[0].hash == "new" && result[0].size == 2)
    }

    @Test func linksTexToSameNamedPDF() throws {
        let scanned: [ScannedEntry] = [.init(path: "Exams/Midterm/Problems.pdf"), .init(path: "Exams/Midterm/Problems.tex")]
        let result = try MaterialTracking.reconcile([], with: scanned, io: io(), device: device, now: t1)
        let pdf = try #require(result.first { $0.path.hasSuffix(".pdf") })
        #expect(result.first { $0.path.hasSuffix(".tex") }?.sourceOf == pdf.id)
    }
}
