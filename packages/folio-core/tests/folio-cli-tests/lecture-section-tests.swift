@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

/// A lecture's sections on its units (#321): `unit pages` and `material split`.
struct LectureSectionCommandTests {
    let h = Harness()
    let course = Harness.graphTheory
    static let track = MaterialNoteStudyTests.track
    static let konig = UUID(uuidString: "A0000000-0000-4000-8000-0000000000F1")!
    static let addKonig = ["unit", "add", "EC4207", "König", "--id", konig.uuidString]
    static let addPages = ["unit", "pages", "add", "EC4207/König", "05_Matchings.pdf", "--first", "5", "--last", "8"]

    func material(_ gist: GISTStore) throws -> UUID {
        try #require(try h.file(gist).materials.first { $0.path.hasSuffix("05_Matchings.pdf") }).id
    }

    @Test func pagesAdd() throws {
        try h.expectSame(Self.addPages, setup: [Self.track, Self.addKonig]) { gist in
            UnitPagesAdd(course: course, unit: Self.konig, material: try material(gist), first: 5, last: 8)
        }
        let gist = try Harness.fixtureCopy()
        for line in [Self.track, Self.addKonig] { _ = h.cli(line, gist: gist) }
        #expect(h.cli(["unit", "pages", "add", "EC4207/König", "05_Matchings.pdf", "--first", "8", "--last", "5"], gist: gist).code != 0)
        #expect(h.cli(Self.addPages, gist: gist).code == 0)
        #expect(h.cli(["unit", "show", "EC4207/König"], gist: gist).out.contains("05_Matchings.pdf p.5-8"))
    }

    @Test func pagesSet() throws {
        try h.expectSame(["unit", "pages", "set", "EC4207/König", "05_Matchings.pdf", "--first", "4", "--last", "9"],
                         setup: [Self.track, Self.addKonig, Self.addPages]) { gist in
            UnitPagesSet(course: course, unit: Self.konig, material: try material(gist), first: 4, last: 9)
        }
    }

    @Test func pagesRemove() throws {
        try h.expectSame(["unit", "pages", "rm", "EC4207/König", "05_Matchings.pdf", "--yes"], setup: [Self.track, Self.addKonig, Self.addPages]) { gist in
            UnitPagesRemove(course: course, unit: Self.konig, material: try material(gist))
        }
    }

    @Test func split() throws {
        try h.expectSame(["material", "split", "EC4207/05_Matchings.pdf", "1-4:매칭", "5-8:König", "9-13:매칭"],
                         setup: [Self.track, Self.addKonig, Self.addPages]) { gist in
            let made = UUID()
            return MaterialSplit(course: course, material: try material(gist), sections: [
                LectureCut(unit: made, title: "매칭", firstPage: 1, lastPage: 4),
                LectureCut(unit: Self.konig, firstPage: 5, lastPage: 8),
                LectureCut(unit: made, title: "매칭", firstPage: 9, lastPage: 13),
            ])
        }
        let gist = try Harness.fixtureCopy()
        for line in [Self.track, Self.addKonig] { _ = h.cli(line, gist: gist) }
        #expect(h.cli(["material", "split", "EC4207/05_Matchings.pdf", "5-8"], gist: gist).code == Exit.usage.rawValue)
        // A backward cut is refused before anything is written, the new unit included.
        #expect(h.cli(["material", "split", "EC4207/05_Matchings.pdf", "1-4:매칭", "9-5:König"], gist: gist).code != 0)
        #expect(try h.file(GISTStore(url: gist)).units.map(\.title) == ["König"])
    }

    @Test func importSplitsTheLecture() throws {
        let file = try MaterialNoteStudyTests().scratch("Coloring.pdf", "pdf")
        let cuts = [LectureCut(unit: Self.konig, firstPage: 1, lastPage: 3)]
        let gist = try Harness.fixtureCopy()
        for line in [Self.track, Self.addKonig] { _ = h.cli(line, gist: gist) }
        try h.direct(MaterialImport(course: course, items: [ImportItem(file: file, folder: "Lectures", sections: cuts)]), gist: gist)
        let f = try h.file(GISTStore(url: gist))
        let m = try #require(f.materials.first { $0.path == "Lectures/Coloring.pdf" })
        #expect(f.units.first { $0.id == Self.konig }?.lecturePages == [UnitPages(materialId: m.id, firstPage: 1, lastPage: 3)])
    }
}
