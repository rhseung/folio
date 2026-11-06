import AppKit
import FolioDomain
import FolioMarkdown
import SwiftUI
import Testing
@testable import Folio

/// Typing help in the edit view, driven by the keys the text view gets: the completion menu, pairs and snippets, and
/// that none of them acts while a Hangul syllable is being composed.
@MainActor @Suite(.serialized)
struct NoteAssistTests {
    static let none = NSRange(location: NSNotFound, length: 0)

    static func editor(_ text: String, syntax: MathSyntax = .latex) -> (SourceTextView, NSWindow) {
        let (view, window) = NoteSourceTests.typing(text)
        view.configure(accent: CourseAccent.presets[0].accent, syntax: syntax, dark: false)
        view.setAssist(NoteAssist(), syntax: syntax)
        return (view, window)
    }

    static func type(_ view: SourceTextView, _ keys: String) {
        for key in keys { view.insertText(String(key), replacementRange: none) }
    }

    static func caretShown(_ view: SourceTextView) -> String {
        (view.string as NSString).replacingCharacters(in: NSRange(location: view.selectedRange().location, length: 0), with: "|")
    }

    static func enter(_ view: SourceTextView) { view.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
    static func tab(_ view: SourceTextView) { view.doCommand(by: #selector(NSResponder.insertTab(_:))) }

    @Test func pairsCloseAsTyped() {
        let (view, _) = Self.editor("")
        Self.type(view, "값 $x")
        #expect(Self.caretShown(view) == "값 $x|$")
        Self.type(view, "$ (a")
        #expect(Self.caretShown(view) == "값 $x$ (a|)")
        view.deleteBackward(nil)
        view.deleteBackward(nil)
        #expect(Self.caretShown(view) == "값 $x$ |")
    }

    @Test func slashOpensTheBlockMenu() {
        let (view, _) = Self.editor("")
        Self.type(view, "/")
        #expect(view.completion.visible && view.completion.query?.kind == .slash)
        Self.type(view, "표")
        #expect(view.completion.current?.id == "slash.table")
        Self.enter(view)
        #expect(view.string.hasPrefix("|  |  |\n| --- | --- |") && !view.completion.visible)
    }

    @Test func aCalloutFromTheMenuAsksForItsType() {
        let (view, _) = Self.editor("")
        Self.type(view, "/callout")
        Self.enter(view)
        #expect(view.string == "> [!" && view.completion.query?.kind == .callout)
        Self.type(view, "def")
        Self.tab(view)
        #expect(Self.caretShown(view) == "> [!definition] |")
    }

    @Test func aFenceOffersItsLanguages() {
        let (view, _) = Self.editor("")
        Self.type(view, "```")
        #expect(view.string == "```" && view.completion.query?.kind == .codeLanguage)
        #expect(view.completion.items.contains { $0.title == "python" } && view.completion.items.contains { $0.title == "cb-table" })
        Self.type(view, "sw")
        Self.enter(view)
        #expect(Self.caretShown(view) == "```swift\n|\n```")
    }

    @Test func texCommandsTakeTabThroughTheirArguments() {
        let (view, _) = Self.editor("")
        Self.type(view, "$\\fr")
        #expect(view.completion.current?.title == "\\frac")
        Self.enter(view)
        #expect(Self.caretShown(view) == "$\\frac{|}{}$" && !view.completion.visible)
        Self.type(view, "a")
        view.insertTab(nil)
        Self.type(view, "b")
        view.insertTab(nil)
        #expect(Self.caretShown(view) == "$\\frac{a}{b}$|")
    }

    @Test func environmentsCloseThemselves() {
        let (view, _) = Self.editor("$$\n\n$$")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        Self.type(view, "\\begin{pm")
        Self.enter(view)
        #expect(Self.caretShown(view) == "$$\n\\begin{pmatrix}\n|\n\\end{pmatrix}\n$$")
    }

    @Test func snippetsExpandFromTheMenuOrOnTab() {
        let (view, _) = Self.editor("")
        Self.type(view, "값 mk")
        #expect(view.completion.query?.kind == .snippet)
        Self.tab(view)
        #expect(Self.caretShown(view) == "값 $|$")
        Self.type(view, "x //")
        view.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(!view.completion.visible)
        view.insertTab(nil)
        #expect(Self.caretShown(view) == "값 $x \\frac{|}{}$")
    }

    @Test func asciiMathNotesGetNoTeXCommands() {
        let (view, _) = Self.editor("", syntax: .asciimath)
        Self.type(view, "$\\fr")
        #expect(!view.completion.visible)
    }

    @Test func arrowsMoveThePickAndAClickTakesOne() {
        let (view, _) = Self.editor("")
        Self.type(view, "/")
        view.doCommand(by: #selector(NSResponder.moveDown(_:)))
        #expect(view.completion.selected == 1)
        view.doCommand(by: #selector(NSResponder.moveUp(_:)))
        view.doCommand(by: #selector(NSResponder.moveUp(_:)))
        #expect(view.completion.selected == view.completion.items.count - 1)
        view.acceptCompletion(view.completion.items.firstIndex { $0.id == "slash.quote" })
        #expect(view.string == "> ")
    }

    /// The input method owns the keys while a syllable is marked: no pair closes under it, the menu takes no key and
    /// doesn't narrow, and a list doesn't carry on. Once the syllable is done, all of it applies again.
    @Test func composingHangulIsLeftAlone() throws {
        let (view, _) = Self.editor("")
        Self.type(view, "/")
        let items = view.completion.items
        view.setMarkedText("ㅍ", selectedRange: NSRange(location: 1, length: 0), replacementRange: Self.none)
        #expect(view.completion.items == items)
        view.setMarkedText("표", selectedRange: NSRange(location: 1, length: 0), replacementRange: Self.none)
        #expect(view.string == "/표" && view.hasMarkedText() && view.completion.items == items)
        view.insertText("표", replacementRange: Self.none)
        #expect(!view.hasMarkedText() && view.completion.current?.id == "slash.table")
        // Return while the next syllable is marked is the input method's, not the menu's.
        view.setMarkedText("ㄱ", selectedRange: NSRange(location: 1, length: 0), replacementRange: Self.none)
        Self.enter(view)
        #expect(!view.string.contains("---"))

        // A symbol the input method puts in place of the marked syllable is typed as it is.
        let (list, _) = Self.editor("- 하나")
        list.setMarkedText("ㄷ", selectedRange: NSRange(location: 1, length: 0), replacementRange: Self.none)
        list.insertText("(", replacementRange: list.markedRange())
        #expect(list.string == "- 하나(")
        list.setMarkedText("ㄷ", selectedRange: NSRange(location: 1, length: 0), replacementRange: Self.none)
        list.insertNewline(nil)
        #expect(!list.string.contains("\n- "))

        // A syllable composed inside a pair stays whole and keeps the closer after it.
        let (pair, _) = Self.editor("")
        Self.type(pair, "(")
        pair.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: Self.none)
        pair.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: Self.none)
        #expect(pair.string == "(하)")
        pair.insertText("하", replacementRange: Self.none)
        Self.type(pair, ")")
        #expect(Self.caretShown(pair) == "(하)|")
    }

    /// The edit view with the menu over it, to look at the menu: offscreen, AppKit draws neither the menu's hosting
    /// view nor glass, so SwiftUI draws the menu on the card color where the view put it.
    static func writeWithMenu(_ view: SourceTextView, _ name: String, dark: Bool) throws {
        guard let dir = ProcessInfo.processInfo.environment["FOLIO_NOTE_RENDER"] else { return }
        let host = try #require(view.menuHost)
        let scroll = try #require(view.enclosingScrollView)
        let area = NSRect(x: 0, y: 0, width: view.bounds.width, height: 400)
        let text = try #require(view.bitmapImageRepForCachingDisplay(in: area))
        view.cacheDisplay(in: area, to: text)
        // The rows without their scroll view, which ImageRenderer leaves empty.
        let rows = CompletionMenuView(menu: view.completion) { _ in }.rows
            .frame(width: CompletionMenuView.width, height: CompletionMenuView.height(rows: view.completion.items.count), alignment: .top)
            .clipped()
        let renderer = ImageRenderer(content: rows
            .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.floating))
            .environment(\.accent, CourseAccent.presets[0].accent)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        let menu = try #require(renderer.nsImage)
        let frame = view.convert(host.frame, from: scroll)
        let back = dark ? NSColor(white: 0.12, alpha: 1) : NSColor.white
        let out = NSImage(size: area.size, flipped: false) { _ in
            back.setFill()
            area.fill()
            text.draw(in: area)
            // The text view is flipped and the image isn't.
            menu.draw(in: NSRect(x: frame.minX, y: area.height - frame.maxY, width: frame.width, height: frame.height))
            return true
        }
        let rep = try #require(out.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: dir).appending(path: "\(name).png"))
    }

    @Test func renderMenu() throws {
        for dark in [false, true] {
            let (view, window) = Self.editor("# 행렬\n\n고윳값은 ", syntax: .latex)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            Self.type(view, "$\\la")
            try Self.writeWithMenu(view, "assist-tex-\(dark ? "dark" : "light")", dark: dark)
            let (slash, other) = Self.editor("# 행렬\n\n", syntax: .latex)
            other.appearance = window.appearance
            Self.type(slash, "/")
            try Self.writeWithMenu(slash, "assist-slash-\(dark ? "dark" : "light")", dark: dark)
        }
    }
}
