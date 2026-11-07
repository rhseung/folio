import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct MaterialImportTests {
    static let course = ActionTests.graphTheory
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore
    let store: CourseStore
    let outside = FileManager.default.temporaryDirectory.appending(path: "folio-import-\(UUID().uuidString)")

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
        store = try ActionContext(gist: gist, device: device).store(Self.course)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    func run(_ action: some Action, dryRun: Bool = false) throws {
        try action.run(ActionContext(gist: gist, device: device, now: now, dryRun: dryRun))
    }

    func file() throws -> CourseFile { try ActionContext(gist: gist, device: device).file(Self.course) }

    func download(_ name: String) throws -> String {
        let url = outside.appending(path: name)
        try Data(name.utf8).write(to: url)
        return url.path
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: store.url.appending(path: path).path) }

    /// Each file has its own folder and class, and a lecture takes its class's week, not one week for all.
    @Test func eachFileGoesToItsOwnFolderAndSession() throws {
        let session = UUID()
        try run(SessionAdd(id: session, course: Self.course, date: now, topic: "Hall"))
        let week = try #require(try file().sessions.first { $0.id == session }).week
        try run(MaterialImport(course: Self.course, items: [
            ImportItem(file: try download("Hall.pdf"), folder: "Lectures", session: session),
            ImportItem(file: try download("Diestel.pdf"), folder: "Textbooks"),
            // Already named for its week: kept, and still linked.
            ImportItem(file: try download("05-2_König.pdf"), folder: "Lectures", session: session),
        ]))
        let lecture = String(format: "Lectures/%02d_Hall.pdf", week)
        #expect(exists(lecture) && exists("Textbooks/Diestel.pdf") && exists("Lectures/05-2_König.pdf"))
        let f = try file()
        let linked = Set(try #require(f.sessions.first { $0.id == session }).materials.compactMap { m in f.materials.first { $0.id == m.materialId }?.path })
        #expect(linked == [lecture, "Lectures/05-2_König.pdf"])
    }

    /// The same name twice, or a name the folder holds, gets ` 2`, ` 3`, never an overwrite.
    @Test func sameNamesAreNumbered() throws {
        let first = try download("05_Matchings.pdf")
        try run(MaterialImport(course: Self.course, items: [ImportItem(file: first, folder: "Lectures"), ImportItem(file: first, folder: "Lectures")]))
        #expect(exists("Lectures/05_Matchings 2.pdf") && exists("Lectures/05_Matchings 3.pdf"))
    }

    /// One file that can't go in stops the rest before anything is copied.
    @Test func oneBlockedItemWritesNothing() throws {
        let good = try download("Notes.pdf")
        #expect(throws: ActionError.self) {
            try run(MaterialImport(course: Self.course, items: [ImportItem(file: good, folder: "Study"), ImportItem(file: good, folder: "../Elsewhere")]))
        }
        #expect(throws: ActionError.self) {
            try run(MaterialImport(course: Self.course, items: [ImportItem(file: good, folder: "Study"), ImportItem(file: good, folder: "Study", session: UUID())]))
        }
        #expect(throws: ActionError.self) {
            try run(MaterialImport(course: Self.course, items: [ImportItem(file: good, folder: "Study"), ImportItem(file: outside.appending(path: "gone.pdf").path, folder: "Study")]))
        }
        #expect(!exists("Study/Notes.pdf"))
    }

    @Test func dryRunCopiesNothing() throws {
        try run(MaterialImport(course: Self.course, items: [ImportItem(file: try download("Plan.pdf"), folder: "Study")]), dryRun: true)
        #expect(!exists("Study/Plan.pdf"))
    }
}
