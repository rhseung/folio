import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import PDFKit
import Testing
@testable import Folio

/// A lecture's units (#321): proposed in the add sheet, edited on the split screen, and drawn where its progress shows.
@MainActor
struct LectureSectionsModelTests {
    let workspace: Workspace
    let slides: FolioDomain.Material
    let matching: UUID

    init() throws {
        workspace = try fixtureWorkspace()
        workspace.run(MaterialTrack(course: graphTheory))
        slides = try #require(workspace.course(graphTheory)?.file.materials.first { $0.path == "Lectures/05_Matchings.pdf" })
        matching = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
    }

    var file: CourseFile { workspace.course(graphTheory)!.file }

    /// A file outside the course, as the add sheet gets it.
    func incoming(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "folio-sections-\(UUID().uuidString)").appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: url)
        return url
    }

    func proposal(_ units: [FolioDomain.Unit]) -> LectureSplit {
        let found = LectureSplit([.init(title: "Matchings", firstPage: 1, lastPage: 1), .init(title: "Berge", firstPage: 9, lastPage: 9)], pageCount: 16)!
        var split = SectionMatch.match(found, units: units)
        split.setUnit(units.first { $0.title == "매칭" }?.id, of: 0, match: .name)
        return split
    }

    func settle(_ model: ImportPlaceModel) async {
        for _ in 0..<50 {
            if case .reading? = model.sections(of: model.rows[0]) { await Task.yield() } else { return }
        }
    }

    // MARK: The add sheet

    @Test func aLectureComesInWithTheSectionsKept() async throws {
        let course = try #require(workspace.course(graphTheory))
        let url = try incoming("06_Matchings II.pdf")
        let model = ImportPlaceModel(workspace: workspace, course: course, files: [url], places: []) { _, units, progress in
            progress(16, 16)
            return .found(proposal(units), .outline)
        }
        await settle(model)
        let row = model.rows[0]
        #expect(model.opened == [0])
        #expect(model.sectionsLine(row) == "단원 2구역 · 목차에서")
        var split = try #require(model.edit(0))
        split.moveBoundary(after: 0, to: 10)
        model.setSplit(split, of: 0)
        model.confirm()

        let f = file
        let m = try #require(f.materials.first { $0.path.hasSuffix("06_Matchings II.pdf") })
        #expect(f.units.first { $0.id == matching }?.lecturePages == [UnitPages(materialId: m.id, firstPage: 1, lastPage: 10)])
        #expect(f.units.first { $0.title == "Berge" }?.lecturePages == [UnitPages(materialId: m.id, firstPage: 11, lastPage: 16)])
    }

    /// Put off, the file comes in unsplit, but what was proposed comes back on asking; a row turned into an assignment
    /// takes no sections at all.
    @Test func putOffOrNoLongerALectureWritesNoSections() async throws {
        let course = try #require(workspace.course(graphTheory))
        let model = ImportPlaceModel(workspace: workspace, course: course, files: [try incoming("07_Flows.pdf")],
                                     places: MaterialIntake.places(assignmentFolders: ["HW01"])) { _, units, _ in .found(proposal(units), .claude) }
        await settle(model)
        model.later(0)
        #expect(model.sectionsLine(model.rows[0]) == "단원 구간 없음 · 나중에 나누기")
        #expect(model.cuts(model.rows[0]) == nil)
        model.takeBack(0)
        #expect(model.sectionsLine(model.rows[0]) == "단원 2구역 · Claude 제안")
        model.setFolder("Assignments/HW01", for: [0])
        #expect(model.sections(of: model.rows[0]) == nil && model.cuts(model.rows[0]) == nil)
    }

    @Test func nothingFoundSplitsByHand() async throws {
        let course = try #require(workspace.course(graphTheory))
        let model = ImportPlaceModel(workspace: workspace, course: course, files: [try incoming("a.pdf"), try incoming("b.pdf")], places: []) { _, _, _ in
            .nothing(pageCount: 12)
        }
        await settle(model)
        // Two files: each keeps to its line.
        #expect(model.opened.isEmpty)
        #expect(model.sectionsLine(model.rows[0]) == "목차와 슬라이드 제목을 찾지 못했습니다")
        model.splitByHand(0)
        #expect(model.edit(0)?.sections.map(\.pages) == [1...12] && model.opened == [0])
        // One zone for no unit writes nothing.
        #expect(model.cuts(model.rows[0]) == nil)
    }

    // MARK: The split screen and the bars

    @Test func theSplitScreenSavesTheWholeSplit() async throws {
        let course = try #require(workspace.course(graphTheory))
        let model = FileViewModel(workspace: workspace, course: course, subject: .material(slides.id))
        #expect(model.canSplit)
        let document = PDFDocument()
        for i in 0..<10 { document.insert(PDFPage(), at: i) }
        let controller = PDFController(document: document, page: 0)
        await model.startSplit(controller)
        // The fixture's file isn't a PDF to read: one zone to cut by hand, and the screen says so.
        #expect(model.splitting?.sections.map(\.pages) == [1...10])
        #expect(model.splitNote == String(localized: .fileViewSplitNothing))
        model.splitting?.split(at: 5)
        model.splitting?.setUnit(matching, of: 1)
        model.saveSplit()
        #expect(model.splitting == nil)
        #expect(file.units.first { $0.id == matching }?.lecturePages == [UnitPages(materialId: slides.id, firstPage: 5, lastPage: 10)])

        // Opened again, it starts from what the course holds.
        await model.startSplit(controller)
        #expect(model.splitting?.sections.map(\.pages) == [1...4, 5...10] && model.splitting?.sections[1].unit == matching)
    }

    @Test func theProgressBarReadsTheUnitsItReaches() throws {
        workspace.run(MaterialSplit(course: graphTheory, material: slides.id, sections: [LectureCut(unit: matching, firstPage: 3, lastPage: 8)]))
        let session = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now))?.made)
        let model = SessionProgressModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.sections(slides.id).map(\.pages) == [1...2, 3...8])
        #expect(model.sections(slides.id).map(\.title) == ["", "매칭"])
        #expect(model.reads(slides.id)(5...12) == "매칭")
        #expect(model.reads(slides.id)(1...2) == nil)
        #expect(!model.edited)

        let units = UnitsModel(workspace: workspace, courseId: graphTheory)
        workspace.run(MaterialLinkUnit(course: graphTheory, material: slides.id, unit: matching, linked: true))
        let unit = try #require(file.units.first { $0.id == matching })
        #expect(units.materials(unit, in: file).first { $0.material.id == slides.id }?.pages == 3...8)
    }
}
