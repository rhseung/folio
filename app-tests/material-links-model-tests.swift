import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

/// The units page, the materials list, review and the exam card read the same links (`CourseFile.routes(of:to:)`).
@MainActor
struct MaterialLinksModelTests {
    let workspace: Workspace
    let unit: UUID
    let session: UUID

    init() throws {
        workspace = try fixtureWorkspace()
        workspace.run(MaterialTrack(course: graphTheory))
        unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        session = try #require(workspace.run(SessionAdd(course: graphTheory, date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!))?.made)
        workspace.run(UnitLink(course: graphTheory, unit: unit, sessions: [session]))
    }

    var file: CourseFile { workspace.course(graphTheory)!.file }
    func material(_ path: String) throws -> FolioDomain.Material { try #require(file.materials.first { $0.path == path }) }
    func theUnit() throws -> FolioDomain.Unit { try #require(file.units.first { $0.id == unit }) }

    /// The list shows `Study/Problems.pdf` only through `Problems.tex` (#109), so that row is where its links show.
    @Test func aTexRowCarriesItsHiddenPDFsLinks() throws {
        let tex = try material("Study/Problems.tex")
        let pdf = try material("Study/Problems.pdf")
        workspace.run(MaterialLinkUnit(course: graphTheory, material: pdf.id, unit: unit))
        let model = MaterialsModel(workspace: workspace, course: try #require(workspace.course(graphTheory)))
        let section = try #require(model.sections().first { $0.rows.contains { $0.id == tex.id.uuidString } })
        #expect(section.pdfs[tex.id]?.id == pdf.id)
        #expect(!section.rows.contains { $0.id == pdf.id.uuidString })
        #expect(model.linkLine(tex, pdf: section.pdfs[tex.id]) == "PDF: 단원: 매칭")
        #expect(model.linkLine(tex, pdf: nil) == "")
    }

    @Test func aUnitsClassFileIsMarkedAndLinkingItMakesItTheUnits() throws {
        let slides = try material("Lectures/05_Matchings.pdf")
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: session, firstPage: 3, lastPage: 8))
        let model = UnitsModel(workspace: workspace, courseId: graphTheory)
        let row = try #require(model.materials(try theUnit(), in: file).first)
        #expect(row.material.id == slides.id && !row.own)
        #expect(row.detail.hasSuffix(" p.3–8"))
        #expect(try material(slides.path).unitIds.isEmpty)

        #expect(model.materialMenu(try theUnit(), in: file).first { $0.id == slides.id }?.on == false)
        model.toggle(material: slides.id, in: try theUnit(), file: file)
        #expect(try material(slides.path).unitIds == [unit])
        #expect(model.materials(try theUnit(), in: file).first?.own == true)
        #expect(model.materialMenu(try theUnit(), in: file).first { $0.id == slides.id }?.on == true)
    }

    @Test func theMaterialsListTellsUnitsThroughAClassApart() throws {
        let slides = try material("Lectures/05_Matchings.pdf")
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: session))
        let model = MaterialsModel(workspace: workspace, course: try #require(workspace.course(graphTheory)))
        #expect(model.linkLine(slides).hasSuffix("회차로 단원: 매칭"))
        #expect(model.unitsViaSessions(of: slides.id) == [unit])
        model.link(slides.id, unit: unit, linked: true)
        let line = model.linkLine(try material(slides.path))
        #expect(line.hasSuffix("단원: 매칭") && !line.contains("회차로"))
        #expect(model.unitsViaSessions(of: slides.id).isEmpty)
    }

    @Test func reviewOpensTheUnitsOwnFilesToo() throws {
        let slides = try material("Lectures/05_Matchings.pdf"), study = try material("Study/Problems.pdf")
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: session, firstPage: 4))
        workspace.run(MaterialLinkUnit(course: graphTheory, material: study.id, unit: unit, linked: true))
        let model = ReviewModel(workspace: workspace, items: [.init(courseId: graphTheory, unitId: unit)])
        let current = try #require(model.current)
        model.load(course: current.course, unit: current.unit)
        #expect(model.sources.map(\.id) == [.lecture(slides.id), .lecture(study.id)])
        #expect(model.sources.map(\.page) == [4, nil])
    }

    @Test func anExamCardLinksFilesFromOutsideItsFolder() throws {
        let exam = try #require(workspace.run(ExamAdd(course: graphTheory, title: "Midterm"))?.made)
        let model = ExamsModel(workspace: workspace, course: try #require(workspace.course(graphTheory)))
        let theExam = { try #require(self.file.exams.first { $0.id == exam }) }
        let study = try material("Study/Problems.pdf")
        // The folder's own files belong already, so the picker leaves them out.
        #expect(try !model.materialMenu(theExam()).contains { $0.label.hasPrefix("Exams/Midterm/") })
        #expect(try model.fileCount(theExam()) == 2 && model.linkedMaterials(theExam()).isEmpty)
        model.toggle(material: study.id, in: try theExam())
        #expect(try material(study.path).examIds == [exam])
        #expect(try model.linkedMaterials(theExam()).map(\.path) == ["Study/Problems.pdf"])
        #expect(try model.fileCount(theExam()) == 3)

        let materials = MaterialsModel(workspace: workspace, course: try #require(workspace.course(graphTheory)))
        #expect(try materials.routes(of: study.id, to: theExam()) == [.direct])
        #expect(try materials.routes(of: try material("Exams/Midterm/Guideline.pdf").id, to: theExam()) == [.folder])
        materials.link(study.id, exam: exam, linked: false)
        #expect(try model.linkedMaterials(theExam()).isEmpty)
    }
}
