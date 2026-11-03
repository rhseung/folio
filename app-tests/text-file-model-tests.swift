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

    /// A `.tex` note saves through `note write` and keeps its PDF in Notes/Exports, not among the notes.
    @Test func aTexNoteOpensAsAFile() throws {
        let id = try #require(workspace.run(NoteAdd(course: graphTheory, title: "증명", format: .tex))?.made)
        let note = try #require(try workspace.course(graphTheory)?.store.note(id: id))
        let model = TextFileModel(workspace: workspace, course: course, source: .note(note))
        model.load()
        #expect(model.isTex && model.path == "Notes/증명.tex" && model.pdfPath == "Notes/Exports/증명.pdf")
        model.text = "\\documentclass{article}\n"
        model.saveIfDirty()
        #expect(!model.dirty && model.issues.isEmpty)
        #expect(try course.store.readText("Notes/증명.tex") == "\\documentclass{article}\n")
        // The link menu on the same screen changes the kind, and with it where the build puts the PDF.
        workspace.run(NoteLink(course: graphTheory, note: id, kind: .examSummary))
        #expect(model.pdfPath == "Exercises/증명.pdf")
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
        let namesake = TexIssue(.error, file: "sections/Problems.tex", line: 9, message: "Undefined control sequence")
        #expect(!model.isHere(namesake))
        #expect(model.isHere(TexIssue(.error, file: "./Problems.tex", line: 1, message: "x")))
    }

    /// An empty editor over a file that couldn't be read would look like an empty file, and saving would replace it.
    @Test func aFileThatCantBeReadDoesNotOpenEmpty() throws {
        try Data([0xC7, 0xD1, 0x0A]).write(to: course.store.fileURL("Exams/Midterm/Problems.tex"))
        let model = try model("Exams/Midterm/Problems.tex")
        #expect(model.unreadable && !model.dirty)
        model.text = "x"
        model.saveNow(force: true)
        #expect(try Data(contentsOf: course.store.fileURL("Exams/Midterm/Problems.tex")) == Data([0xC7, 0xD1, 0x0A]))
    }

    @Test func materialsOpenTextHereAndOthersElsewhere() throws {
        let materials = MaterialsModel(workspace: workspace, course: course)
        let tex = try #require(course.file.materials.first { $0.path == "Exams/Midterm/Problems.tex" })
        #expect(tex.isText && !tex.isPDF)
        materials.open(tex)
        #expect(materials.viewing == tex.id)
    }
}
