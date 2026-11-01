import AppKit
import FolioDomain
import Testing
@testable import Folio

/// Changing the text or its look must not move what's on screen: TextKit 2 guesses the height of text it hasn't laid out,
/// so a note with tall pictures above the screen jumps unless every change puts its line back where it was.
@MainActor @Suite(.serialized)
struct NoteScrollTests {
    /// Paragraphs with inline math, each with a display equation drawn under it, so the guessed heights are off.
    static let filler = (1...30).map { "문단 \($0) 본문 $a_{\($0)}$ 입니다.\n\n$$\n\\sum_{k=1}^{\($0)} k^2\n$$\n" }.joined(separator: "\n")

    /// A view in a window shorter than the note, laid out to its end so it scrolls.
    static func host(_ view: NSTextView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        let scroll = NoteScrollView(document: view)
        scroll.frame = window.contentView!.bounds
        window.contentView!.addSubview(scroll)
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 400)
        return window
    }

    /// As in the app, only what's on screen is laid out; the rest is TextKit's guess.
    static func fit(_ view: NSTextView) {
        view.textLayoutManager?.textViewportLayoutController.layoutViewport()
        view.setFrameSize(NSSize(width: 900, height: 8000))
    }

    /// Brings character `i` on screen the way the text view does for a caret.
    static func reveal(_ view: NSTextView, _ i: Int) {
        let clip = view.enclosingScrollView!.contentView
        clip.scroll(to: NSPoint(x: 0, y: 2500))
        view.enclosingScrollView!.reflectScrolledClipView(clip)
        view.textLayoutManager?.textViewportLayoutController.layoutViewport()
        view.scrollRangeToVisible(NSRange(location: i, length: 0))
    }

    /// Where the line holding `i` is drawn on screen, from the layout TextKit has, without laying out more.
    static func shown(_ view: NSTextView, _ i: Int) -> CGFloat? {
        guard let manager = view.textLayoutManager, let clip = view.enclosingScrollView?.contentView,
              let location = manager.location(manager.documentRange.location, offsetBy: i) else { return nil }
        manager.textViewportLayoutController.layoutViewport()
        return manager.textLayoutFragment(for: location).map { $0.layoutFragmentFrame.minY + view.textContainerOrigin.y - clip.bounds.minY }
    }

    static func source(_ text: String) -> (SourceTextView, NSWindow) {
        let view = SourceTextView()
        view.delegate = view
        let window = host(view)
        view.baseURL = NoteReaderTests.fixtures
        view.load(text)
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .latex, dark: false)
        fit(view)
        window.makeFirstResponder(view)
        return (view, window)
    }

    final class Body {
        var text: String
        init(_ text: String) { self.text = text }
    }

    static func reader(_ body: Body) -> (ReaderTextView, NSWindow) {
        let view = ReaderTextView()
        let window = host(view)
        view.baseURL = NoteReaderTests.fixtures
        view.edit = { from, to, old, new in
            var lines = body.text.components(separatedBy: "\n")
            guard lines[(from - 1)...(to - 1)].joined(separator: "\n") == old else { return false }
            lines.replaceSubrange((from - 1)...(to - 1), with: new.components(separatedBy: "\n"))
            body.text = lines.joined(separator: "\n")
            return true
        }
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .latex, dark: false)
        view.show(body.text)
        fit(view)
        return (view, window)
    }

    @Test func typingInlineMathKeepsTheLineStill() throws {
        let text = Self.filler + "\n여기에 수식을 쓴다\n\n" + Self.filler
        let (view, _) = Self.source(text)
        let line = (text as NSString).range(of: "여기에").location
        view.setSelectedRange(NSRange(location: line + "여기에 수식을 쓴다".utf16.count, length: 0))
        Self.reveal(view, line)
        let before = try #require(Self.shown(view, line))
        for piece in [" ", "$", "x", "^", "{", "2", "}", "$", " ", "$$"] {
            view.insertText(piece, replacementRange: view.selectedRange())
            #expect(abs(try #require(Self.shown(view, line)) - before) <= 1, "after \(piece.debugDescription)")
        }
    }

    @Test func tickingABoxInTheSourceLeavesTheScreen() throws {
        let text = Self.filler + "\n- [ ] 할 일\n\n" + Self.filler
        let (view, _) = Self.source(text)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let box = (text as NSString).range(of: "[ ] 할 일").location
        Self.reveal(view, box)
        let before = try #require(Self.shown(view, box))
        #expect(view.toggleTask(at: box + 1))
        #expect(view.string.contains("- [x] 할 일"))
        #expect(abs(try #require(Self.shown(view, box)) - before) <= 1)
        #expect(view.selectedRange().location == 0)
    }

    @Test func openingAFoldedCalloutKeepsItsTitleStill() throws {
        let body = Body(Self.filler + "\n> [!note]- 접힌 콜아웃\n> 안의 본문\n> 둘째 줄\n\n" + Self.filler)
        let (view, _) = Self.reader(body)
        let title = (view.string as NSString).range(of: "접힌 콜아웃").location
        Self.reveal(view, title)
        let before = try #require(Self.shown(view, title))
        #expect(view.click(at: title))
        #expect(view.string.contains("안의 본문"))
        #expect(abs(try #require(Self.shown(view, (view.string as NSString).range(of: "접힌 콜아웃").location)) - before) <= 1)
    }

    @Test func tickingABoxInTheReaderKeepsItStill() throws {
        let body = Body(Self.filler + "\n- [ ] 할 일\n- [ ]\n\n" + Self.filler)
        let (view, _) = Self.reader(body)
        let item = (view.string as NSString).range(of: "할 일").location
        Self.reveal(view, item)
        let before = try #require(Self.shown(view, item))
        let box = try #require((item - 4..<item).first { view.textStorage?.attribute(.noteTask, at: $0, effectiveRange: nil) != nil })
        #expect(view.click(at: box))
        #expect(body.text.contains("- [x] 할 일"))
        view.show(body.text)
        #expect(abs(try #require(Self.shown(view, (view.string as NSString).range(of: "할 일").location)) - before) <= 1)
        // A bare `- [ ]` is a box too, and ticks.
        let bare = try #require(view.textStorage.map { s in
            (0..<s.length).last { s.attribute(.noteTask, at: $0, effectiveRange: nil) != nil }
        } ?? nil)
        #expect(view.click(at: bare))
        #expect(body.text.contains("- [x]\n"))
    }
}
