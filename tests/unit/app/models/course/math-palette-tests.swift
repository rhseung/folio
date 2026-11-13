import AppKit
import FolioActions
import FolioDomain
import FolioMarkdown
import Foundation
import Testing

@testable import Folio

@MainActor @Suite(.serialized)
struct MathSymbolsMenuTests {
    static func escape(_ view: SourceTextView) { view.doCommand(by: #selector(NSResponder.cancelOperation(_:))) }

    @Test func aBackslashListsEverySymbolByCategory() {
        let (view, _) = NoteAssistTests.editor("")
        NoteAssistTests.type(view, "값 $x + \\")
        #expect(view.completion.visible && view.completion.query?.kind == .texCommand)
        #expect(view.completion.items.first?.category == .snippets && view.completion.items.contains { $0.title == "\\alpha" })
        NoteAssistTests.type(view, "subsete")
        #expect(view.completion.current?.title == "\\subseteq")
        NoteAssistTests.enter(view)
        #expect(NoteAssistTests.caretShown(view) == "값 $x + \\subseteq|$" && !view.completion.visible)
    }

    @Test func anAsciiMathBackslashGivesWayToTheName() {
        let (view, _) = NoteAssistTests.editor("", syntax: .asciimath)
        NoteAssistTests.type(view, "$x \\")
        #expect(view.completion.items.contains { $0.title == "alpha" } && !view.completion.items.contains { $0.title == "\\alpha" })
        NoteAssistTests.type(view, "sub")
        #expect(view.completion.current?.title == "sub")
        NoteAssistTests.tab(view)
        #expect(NoteAssistTests.caretShown(view) == "$x sub|$")
    }

    @Test func escLeavesABackslashMeantAsOne() {
        let (view, _) = NoteAssistTests.editor("", syntax: .asciimath)
        NoteAssistTests.type(view, "$a\\")
        #expect(view.completion.visible)
        Self.escape(view)
        NoteAssistTests.type(view, " b")
        #expect(NoteAssistTests.caretShown(view) == "$a\\ b|$" && !view.completion.visible)
    }

    @Test func theMenuCommandTypesTheBackslash() {
        let (view, _) = NoteAssistTests.editor("", syntax: .asciimath)
        NoteAssistTests.type(view, "$x + ")
        view.showMathSymbols(nil)
        #expect(NoteAssistTests.caretShown(view) == "$x + \\|$" && view.completion.visible)
        let (text, _) = NoteAssistTests.editor("값 ")
        text.showMathSymbols(nil)
        #expect(text.string == "값 " && !text.completion.visible)
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
        palette.syntax = .asciimath
        #expect(editor.meta.math == .asciimath && palette.sections[0].items.first?.title == "alpha")
    }

    @Test func insideAFenceItsSyntaxHolds() {
        let palette = MathPaletteModel(editor: editor)
        editor.meta.math = .latex
        palette.fence = .asciimath
        palette.category = .greek
        #expect(palette.syntax == .asciimath && palette.sections[0].items.first?.title == "alpha")
        palette.syntax = .asciimath
        #expect(editor.meta.math == .latex)
        palette.fence = nil
        #expect(palette.syntax == .latex && palette.sections[0].items.first?.title == "\\alpha")
    }

    @Test func aPickWaitsForTheEditor() {
        let palette = MathPaletteModel(editor: editor)
        let item = palette.sections[0].items[0]
        palette.pick(item)
        #expect(editor.pendingMath == item)
    }
}
