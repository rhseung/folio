import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing
@testable import Folio

/// 그래프 이론 in the standard fixture has `Exams/Midterm/Problems.tex` next to its PDF.
@MainActor
struct TextFileModelTests {
    let workspace: Workspace
    let course: LoadedCourse

    init() throws {
        workspace = try fixtureWorkspace()
        workspace.run(MaterialTrack(course: graphTheory))
        course = try #require(workspace.course(graphTheory))
    }

    func model(_ path: String) throws -> TextFileModel {
        let m = try #require(course.file.materials.first { $0.path == path })
        let model = TextFileModel(workspace: workspace, course: course, material: m.id)
        model.load()
        return model
    }

    @Test func opensTexWithItsPDF() throws {
        let model = try model("Exams/Midterm/Problems.tex")
        #expect(model.isTex && model.name == "Problems.tex")
        #expect(model.format.highlightLanguage == "latex")
        #expect(model.text == (try course.store.readText("Exams/Midterm/Problems.tex")))
        #expect(model.pdfURL?.lastPathComponent == "Problems.pdf")
        #expect(!model.dirty)
    }

    @Test func savesThroughTheAction() throws {
        let model = try model("Exams/Midterm/Problems.tex")
        model.text = "\\documentclass{article}\n"
        #expect(model.dirty)
        model.saveIfDirty()
        #expect(!model.dirty)
        #expect(try course.store.readText("Exams/Midterm/Problems.tex") == "\\documentclass{article}\n")
    }

    @Test func aChangeElsewhereAsksBeforeOverwriting() throws {
        let model = try model("Exams/Midterm/Problems.tex")
        try course.store.writeText("Exams/Midterm/Problems.tex", text: "바깥에서 고침\n")
        model.text = "여기서 고침\n"
        model.saveNow(force: false)
        #expect(model.conflict)
        #expect(try course.store.readText("Exams/Midterm/Problems.tex") == "바깥에서 고침\n")
        model.saveNow(force: true)
        #expect(!model.conflict)
        #expect(try course.store.readText("Exams/Midterm/Problems.tex") == "여기서 고침\n")
    }

    @Test func onlyThisFilesIssuesJump() throws {
        let model = try model("Exams/Midterm/Problems.tex")
        let here = TexIssue(.error, file: "Problems.tex", line: 3, message: "Undefined control sequence")
        let other = TexIssue(.error, file: "sections/intro.tex", line: 7, message: "Missing $ inserted")
        #expect(model.label(here) == "3번째 줄 · Undefined control sequence")
        #expect(model.label(other) == "sections/intro.tex:7 · Missing $ inserted")
        model.jump(to: other)
        #expect(model.reveal == nil)
        model.jump(to: here)
        #expect(model.reveal == 3)
    }

    @Test func materialsOpenTextHereAndOthersElsewhere() throws {
        let materials = MaterialsModel(workspace: workspace, course: course)
        let tex = try #require(course.file.materials.first { $0.path == "Exams/Midterm/Problems.tex" })
        #expect(tex.isText && !tex.isPDF)
        materials.open(tex)
        #expect(materials.viewing == tex.id)
    }
}
