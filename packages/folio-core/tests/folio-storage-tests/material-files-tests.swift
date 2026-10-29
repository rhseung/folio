import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct MaterialFilesTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func relinkToAPickedFileKeepsLinksThroughSaveAndLoad() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first { $0.url.lastPathComponent == "EC4207 그래프 이론" })
        var doc = try store.load()
        try store.refreshMaterials(in: &doc.model, device: device, now: now)
        let lecture = try #require(doc.model.materials.first { $0.path == "Lectures/05_Matchings.pdf" })
        let session = Session(device: device, at: now, week: 5, index: 1, date: now)
        doc.model.sessions.append(session)
        doc.model.linkMaterial(lecture.id, session: session.id, firstPage: 2, lastPage: 9)
        try store.save(doc)

        // The lecture is replaced by a revised file under another name, so neither bookmark nor hash finds it.
        let fm = FileManager.default
        try fm.removeItem(at: store.url.appending(path: lecture.path))
        let revised = store.url.appending(path: "Lectures/05_Matchings (revised).pdf")
        try Data("revised".utf8).write(to: revised)
        doc = try store.load()
        try store.refreshMaterials(in: &doc.model, device: device, now: now)
        #expect(doc.model.materials.first { $0.id == lecture.id }?.status == .missing)

        try store.relink(lecture.id, to: revised, in: &doc.model, device: device, now: now)
        try store.save(doc)

        let file = try store.load().model
        #expect(file.materials.filter { $0.path == "Lectures/05_Matchings (revised).pdf" }.map(\.id) == [lecture.id])
        #expect(file.materials.first { $0.id == lecture.id }?.status == .classified)
        let link = try #require(file.sessionLinks(of: lecture.id).first?.link)
        #expect((link.firstPage, link.lastPage) == (2, 9))
        #expect(try store.download(file.materials.first { $0.id == lecture.id }!) == store.url.appending(path: "Lectures/05_Matchings (revised).pdf"))

        let outside = gist.url.appending(path: "2026-3/_Admin/2026-3 강의실 배정.pdf")
        #expect(throws: MaterialFileError.self) { try store.relink(lecture.id, to: outside, in: &doc.model, device: device, now: now) }
    }

    @Test func importedFilesNeverOverwriteAndMovesKeepTheMaterialAndUndo() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first { $0.url.lastPathComponent == "EC4207 그래프 이론" })
        let outside = FileManager.default.temporaryDirectory.appending(path: "folio-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let source = outside.appending(path: "slides.pdf")
        try Data("slides".utf8).write(to: source)

        let first = try store.importFile(source, into: "Lectures", name: MaterialIntake.lectureName("slides.pdf", week: 7))
        let second = try store.importFile(source, into: "Lectures", name: MaterialIntake.lectureName("slides.pdf", week: 7))
        #expect((first, second) == ("Lectures/07_slides.pdf", "Lectures/07_slides 2.pdf"))
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(store.coursePath(of: store.fileURL(first)) == first)
        #expect(store.coursePath(of: source) == nil)

        var doc = try store.load()
        try store.refreshMaterials(in: &doc.model, device: device, now: now)
        let m = try #require(doc.model.materials.first { $0.path == second })
        #expect(m.role == .lecture)
        let batch = try store.move(m.id, to: "Archive/old slides.pdf", gist: gist.url, in: &doc.model, device: device, now: now)
        let moved = try #require(doc.model.materials.first { $0.id == m.id })
        #expect(moved.path == "Archive/old slides.pdf" && moved.role == .archive)
        #expect(FileManager.default.fileExists(atPath: store.fileURL("Archive/old slides.pdf").path))

        try MoveJournal.undo(batch: batch, in: gist.url, device: device, now: now)
        #expect(FileManager.default.fileExists(atPath: store.fileURL(second).path))
    }
}
