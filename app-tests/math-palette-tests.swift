import AppKit
import FolioActions
import FolioDomain
import FolioMarkdown
import Foundation
import Testing
@testable import Folio

/// Every symbol of a formula without typing its name first (#392): ⌃Space opens the whole list in the edit view's
/// menu, and the palette under the note bar's f(x) puts what is picked at the caret.
@MainActor @Suite(.serialized)
struct MathSymbolsMenuTests {
    @Test func controlSpaceListsEverySymbolInAFormula() {
        let (view, _) = NoteAssistTests.editor("")
        NoteAssistTests.type(view, "값 $x + ")
        #expect(NoteAssistTests.caretShown(view) == "값 $x + |$")
        view.showMathSymbols(nil)
        #expect(view.completion.visible && view.completion.query?.kind == .mathSymbols)
        #expect(view.completion.items.first?.category == .snippets && view.completion.items.contains { $0.title == "\\alpha" })
        // Typing on narrows it, as the menu that opens by itself does; Return takes the pick.
        NoteAssistTests.type(view, "subsete")
        #expect(view.completion.current?.title == "\\subseteq")
        NoteAssistTests.enter(view)
        #expect(NoteAssistTests.caretShown(view) == "값 $x + \\subseteq|$" && !view.completion.visible)
    }

    @Test func theListFollowsTheNotesSyntaxAndClosesOffTheWord() {
        let (view, _) = NoteAssistTests.editor("", syntax: .asciimath)
        NoteAssistTests.type(view, "$")
        view.showMathSymbols(nil)
        #expect(view.completion.items.contains { $0.title == "alpha" } && !view.completion.items.contains { $0.title == "\\alpha" })
        NoteAssistTests.type(view, "al")
        #expect(view.completion.current?.title == "alpha")
        NoteAssistTests.type(view, " ")
        #expect(!view.completion.visible)
        // Outside a formula there is nothing to list.
        let (text, _) = NoteAssistTests.editor("값 ")
        text.showMathSymbols(nil)
        #expect(!text.completion.visible)
    }

    @Test func aPalettePickGoesInAtTheCaret() {
        let (view, _) = NoteAssistTests.editor("각 ")
        let alpha = MathSymbols.items(tex: true, snippets: []).first { $0.title == "\\alpha" }!
        view.insertMath(alpha)
        #expect(NoteAssistTests.caretShown(view) == "각 $\\alpha|$")
        view.insertMath(alpha)
        #expect(NoteAssistTests.caretShown(view) == "각 $\\alpha\\alpha|$")
    }
}

@MainActor
struct MathPaletteModelTests {
    let workspace: Workspace
    let editor: NoteEditorModel

    init() throws {
        workspace = try fixtureWorkspace()
        let id = try #require(workspace.run(NoteAdd(course: graphTheory, title: "기호", kind: .free))?.made)
        let course = try #require(workspace.course(graphTheory))
        editor = NoteEditorModel(workspace: workspace, course: course, note: try #require(try course.store.note(id: id)))
        editor.load()
    }

    @Test func tabsShowOneCategoryAndSearchLooksThroughAll() {
        let palette = MathPaletteModel(editor: editor)
        editor.meta.math = .latex
        #expect(palette.categories.first == .snippets && palette.category == palette.categories.first)
        palette.category = .greek
        #expect(palette.sections.map(\.category) == [.greek] && palette.sections[0].items.first?.title == "\\alpha")
        palette.search = "arrow"
        #expect(palette.searching && palette.sections.map(\.category) == [.arrows, .fonts])
        palette.search = ""
        // The syntax on top is the note's own, which the f(x) button chose before.
        palette.syntax = .asciimath
        #expect(editor.meta.math == .asciimath && palette.sections[0].items.first?.title == "alpha")
    }

    @Test func aPickWaitsForTheEditor() {
        let palette = MathPaletteModel(editor: editor)
        let item = palette.sections[0].items[0]
        palette.pick(item)
        #expect(editor.pendingMath == item)
    }
}
