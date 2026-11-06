import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

/// The Claude panel, the CLI and other devices write the note that is open. The editor re-reads it when
/// `notesRevision` moves (the view calls `refresh()`), and never replaces edits it hasn't saved.
@MainActor
struct NoteEditorRefreshTests {
    let workspace: Workspace
    let id: UUID
    let path: String
    let editor: NoteEditorModel

    init() throws {
        workspace = try fixtureWorkspace()
        id = try #require(workspace.run(NoteAdd(course: graphTheory, title: "바깥 쓰기", kind: .free))?.made)
        let course = try #require(workspace.course(graphTheory))
        let note = try #require(try course.store.note(id: id))
        path = course.store.notePath(of: note.url)
        editor = NoteEditorModel(workspace: workspace, course: course, note: note)
        editor.load()
    }

    var onDisk: String { get throws { try #require(workspace.course(graphTheory)).store.readText(path) } }

    @Test func aCleanEditorTakesTheNewTextAndLinks() throws {
        let revision = workspace.notesRevision
        workspace.run(NoteWrite(course: graphTheory, note: path, text: "# 바깥에서 쓴 글\n"))
        workspace.run(NoteLink(course: graphTheory, note: id, kind: .free, math: .asciimath))
        #expect(workspace.notesRevision > revision)
        editor.refresh()
        #expect(editor.body == "# 바깥에서 쓴 글\n")
        #expect(editor.meta.math == .asciimath)
        #expect(!editor.dirty && !editor.conflict)
        // The picker now shows the new syntax, which must not count as the user choosing it.
        editor.saveMath()
        #expect(try onDisk == "# 바깥에서 쓴 글\n")
    }

    @Test func unsavedEditsAskInsteadOfOverwriting() throws {
        editor.body += "\n내가 쓰던 글\n"
        workspace.run(NoteWrite(course: graphTheory, note: path, text: "바깥에서 쓴 글\n"))
        workspace.run(NoteLink(course: graphTheory, note: id, kind: .free, math: .asciimath))
        editor.refresh()
        #expect(editor.conflict && editor.dirty)
        #expect(editor.body.hasSuffix("\n내가 쓰던 글\n"))
        // Links live in course.json, apart from the text, so they follow even while the text waits.
        #expect(editor.meta.math == .asciimath)
        editor.saveIfDirty()
        #expect(try onDisk == "바깥에서 쓴 글\n")

        editor.load()
        #expect(editor.body == "바깥에서 쓴 글\n" && !editor.conflict && !editor.dirty)
    }

    @Test func itsOwnSaveReadsNothingAgain() throws {
        editor.body += "\n여기서 쓴 글\n"
        let revision = workspace.notesRevision
        editor.saveNow(force: false)
        #expect(workspace.notesRevision > revision)
        editor.refresh()
        #expect(!editor.conflict && !editor.dirty)
        #expect(editor.body.hasSuffix("\n여기서 쓴 글\n"))
        #expect(try onDisk.hasSuffix("\n여기서 쓴 글\n"))
    }
}
