import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing
@testable import Folio

/// 그래프 이론 in the standard fixture has `Study/Problems.tex` next to its PDF.
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
        let model = try model("Study/Problems.tex")
        #expect(model.isTex && model.name == "Problems.tex")
        #expect(model.format.highlightLanguage == "latex")
        #expect(model.text == (try course.store.readText("Study/Problems.tex")))
        #expect(model.pdfURL?.lastPathComponent == "Problems.pdf")
        #expect(!model.dirty)
    }

    @Test func savesThroughTheAction() throws {
        let model = try model("Study/Problems.tex")
        model.text = "\\documentclass{article}\n"
        #expect(model.dirty)
        model.saveIfDirty()
        #expect(!model.dirty)
        #expect(try course.store.readText("Study/Problems.tex") == "\\documentclass{article}\n")
    }

    @Test func aChangeElsewhereAsksBeforeOverwriting() throws {
        let model = try model("Study/Problems.tex")
        try course.store.writeText("Study/Problems.tex", text: "바깥에서 고침\n")
        model.text = "여기서 고침\n"
        model.saveNow(force: false)
        #expect(model.conflict)
        #expect(try course.store.readText("Study/Problems.tex") == "바깥에서 고침\n")

        model.saveNow(force: true)
        #expect(!model.conflict)
        #expect(try course.store.readText("Study/Problems.tex") == "여기서 고침\n")
    }

    /// A write from the Claude panel or the CLI shows without asking when nothing here is unsaved, asks when something
    /// is, and the screen's own save reads nothing again.
    @Test func aWriteElsewhereReloadsOnlyWhatIsSaved() throws {
        let model = try model("Study/Problems.tex")
        let id = try #require(course.file.materials.first { $0.path == "Study/Problems.tex" }).id
        var revision = model.outsideRevision
        workspace.run(MaterialWrite(course: graphTheory, material: id, text: "바깥에서 고침\n"))
        #expect(model.outsideRevision != revision)
        model.refresh()
        #expect(model.text == "바깥에서 고침\n" && !model.dirty && !model.conflict)

        model.text = "여기서 고침\n"
        model.saveNow(force: false)
        revision = model.outsideRevision
        model.refresh()
        #expect(model.text == "여기서 고침\n" && !model.conflict)

        model.text = "다시 고치는 중\n"
        workspace.run(MaterialWrite(course: graphTheory, material: id, text: "또 바깥에서\n"))
        #expect(model.outsideRevision != revision)
        model.refresh()
        #expect(model.conflict && model.text == "다시 고치는 중\n")
        model.saveIfDirty()
        #expect(try course.store.readText("Study/Problems.tex") == "또 바깥에서\n")
    }

    /// A `.tex` note saves through `note write` and keeps its PDF in Study, not among the notes.
    @Test func aTexNoteOpensAsAFile() throws {
        let id = try #require(workspace.run(NoteAdd(course: graphTheory, title: "증명", format: .tex))?.made)
        let note = try #require(try workspace.course(graphTheory)?.store.note(id: id))
        let model = TextFileModel(workspace: workspace, course: course, source: .note(note))
        model.load()
        #expect(model.isTex && model.path == "Notes/증명.tex" && model.pdfPath == "Study/증명.pdf")
        model.text = "\\documentclass{article}\n"
        model.saveIfDirty()
        #expect(!model.dirty && model.issues.isEmpty)
        #expect(try course.store.readText("Notes/증명.tex") == "\\documentclass{article}\n")

        // Every note exports to Study, so changing the kind from the same screen leaves the place alone.
        workspace.run(NoteLink(course: graphTheory, note: id, kind: .examSummary))
        #expect(model.pdfPath == "Study/증명.pdf")
    }

    /// A `.tex` opens the way it was last left, as a markdown note does: a material by its own ID, a note by its note's.
    @Test func aTexIsRememberedByItsOwnID() throws {
        let tex = try model("Study/Problems.tex")
        let material = try #require(course.file.materials.first { $0.path == "Study/Problems.tex" })
        #expect(tex.paneId == material.id)

        let id = try #require(workspace.run(NoteAdd(course: graphTheory, title: "증명", format: .tex))?.made)
        let note = try #require(try workspace.course(graphTheory)?.store.note(id: id))
        #expect(TextFileModel(workspace: workspace, course: course, source: .note(note)).paneId == id)

        let store = PaneMemoryStore(defaults: try #require(UserDefaults(suiteName: "folio-tests-\(UUID().uuidString)")))
        store.remember(.read, note: material.id)
        #expect(store.memory.noteMode(note: material.id).map { NotePanes(remembered: $0).shown(wide: true) } == .read)
    }

    @Test func onlyThisFilesIssuesJump() throws {
        let model = try model("Study/Problems.tex")
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

    /// A ⌘-click on the PDF goes to the line of this file that wrote there, but only with SyncTeX data from the build
    /// that made the PDF on screen. The data is written by hand so the test runs without Tectonic.
    @Test func aCommandClickOnThePDFShowsItsLine() throws {
        let model = try model("Study/Problems.tex")
        let shown = try #require(model.pdfURL)
        let folder = TexEngine.outputFolder(for: model.fileURL)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: shown, to: folder.appending(path: "Problems.pdf"))
        let synctex = folder.appending(path: "Problems.synctex")
        try """
            SyncTeX Version:1
            Input:1:\(model.fileURL.path)
            Input:2:\(model.fileURL.deletingLastPathComponent().path)/part.tex
            Magnification:1000
            Unit:1
            X Offset:0
            Y Offset:0
            Content:
            {1
            [1,9:8799519,44254495:22609920,36044800,0
            (1,4:8799519,8865055:22609920,454820,7208
            g1,3:11475354,8865055
            )
            (2,6:8799519,9651487:22609920,533465,135003
            g2,5:12003574,9651487
            )
            ]
            }1
            """.write(to: synctex, atomically: true, encoding: .utf8)
        let gzip = Process()
        gzip.executableURL = URL(filePath: "/usr/bin/gzip")
        gzip.arguments = ["-f", synctex.path]
        try gzip.run()
        gzip.waitUntilExit()

        model.showSource(page: 0, at: CGPoint(x: 200, y: 145))
        #expect(model.reveal == nil)  // part.tex's line, not open here
        model.showSource(page: 0, at: CGPoint(x: 200, y: 132))
        #expect(model.reveal == 3)

        model.reveal = nil
        try Data("%PDF-from another Mac".utf8).write(to: shown)
        model.showSource(page: 0, at: CGPoint(x: 200, y: 132))
        #expect(model.reveal == nil)
    }

    /// An empty editor over a file that couldn't be read would look like an empty file, and saving would replace it.
    @Test func aFileThatCantBeReadDoesNotOpenEmpty() throws {
        try Data([0xC7, 0xD1, 0x0A]).write(to: course.store.fileURL("Study/Problems.tex"))
        let model = try model("Study/Problems.tex")
        #expect(model.unreadable && !model.dirty)
        model.text = "x"
        model.saveNow(force: true)
        #expect(try Data(contentsOf: course.store.fileURL("Study/Problems.tex")) == Data([0xC7, 0xD1, 0x0A]))
    }

    @Test func materialsOpenTextHereAndOthersElsewhere() throws {
        let materials = MaterialsModel(workspace: workspace, course: course)
        let tex = try #require(course.file.materials.first { $0.path == "Study/Problems.tex" })
        #expect(tex.isText && !tex.isPDF)
        materials.open(tex)
        #expect(materials.viewing == tex.id)
    }
}
