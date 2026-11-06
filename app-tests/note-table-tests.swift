import AppKit
import FolioDomain
import FolioMarkdown
import Testing
@testable import Folio

/// The table commands in the edit view: their keys and the context menu, which change the source through
/// `TableEditing` and leave every other key alone outside a table.
@MainActor @Suite(.serialized)
struct NoteTableTests {
    static let table = "앞\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n뒤"

    static func editor(caretAfter marker: String) -> (SourceTextView, NSWindow) {
        let (view, window) = NoteAssistTests.editor(Self.table)
        let at = (Self.table as NSString).range(of: marker)
        view.setSelectedRange(NSRange(location: NSMaxRange(at), length: 0))
        return (view, window)
    }

    static func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    @Test func commandReturnAddsARowBelow() {
        let (view, window) = Self.editor(caretAfter: "| 1")
        #expect(view.performKeyEquivalent(with: Self.key(36, "\r", .command, in: window)))
        #expect(NoteAssistTests.caretShown(view) == "앞\n\n| a   | b   |\n| --- | --- |\n| 1   | 2   |\n| |    |     |\n\n뒤")
    }

    @Test func aMoveIntoTheEdgeIsTakenButChangesNothing() {
        let (view, window) = Self.editor(caretAfter: "| 1")
        #expect(view.performKeyEquivalent(with: Self.key(123, String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)), [.command, .control], in: window)))
        #expect(view.string == Self.table)
    }

    @Test func outsideATableTheKeysStayTheTextViews() {
        let (view, window) = Self.editor(caretAfter: "앞")
        #expect(!view.performKeyEquivalent(with: Self.key(36, "\r", .command, in: window)))
        #expect(view.string == Self.table)
    }

    @Test func theMenuOffersWhatCanBeDoneHere() throws {
        let (view, _) = Self.editor(caretAfter: "| 1")
        let table = try #require(TableEditing.table(in: view.string as NSString, selection: view.selectedRange()))
        let item = TableCommands.menu(for: table) { view.apply($0) }
        let items = try #require(item.submenu?.items.filter { !$0.isSeparatorItem })
        #expect(items.count == TableCommand.allCases.count)
        let enabled = Set(items.filter(\.isEnabled).map(\.title))
        #expect(enabled.contains(TableCommands.title(.rowBelow)) && enabled.contains(TableCommands.title(.mergeRight)))
        #expect(!enabled.contains(TableCommands.title(.moveColumnLeft)) && !enabled.contains(TableCommands.title(.unmerge)))
        let merge = try #require(items.first { $0.title == TableCommands.title(.mergeRight) })
        _ = merge.target?.perform(merge.action, with: merge)
        #expect(view.string.contains("```cb-table\n"))
    }

    /// No two table commands share a key.
    @Test func theKeysAreTheirOwn() {
        let shortcuts = TableCommand.allCases.compactMap(TableCommands.shortcut)
        #expect(Set(shortcuts.map { "\($0)" }).count == shortcuts.count)
    }
}
