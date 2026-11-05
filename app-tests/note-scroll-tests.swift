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

    /// The view's frame cut to the note as laid out, as the app's is, instead of `fit`'s room to spare.
    static func trim(_ view: NSTextView) {
        guard let manager = view.textLayoutManager else { return }
        manager.ensureLayout(for: manager.documentRange)
        view.setFrameSize(NSSize(width: 900, height: manager.usageBoundsForTextContainer.height + 2 * view.textContainerInset.height))
    }

    /// One writes at the note's end, so the editor scrolls its last line up to the middle of the screen, not the bottom.
    @Test func theEditorScrollsItsLastLineToTheMiddle() throws {
        let text = Self.filler + "\n끝 줄"
        let (view, _) = Self.source(text)
        Self.trim(view)
        let clip = try #require(view.enclosingScrollView?.contentView)
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: NSPoint(x: 0, y: 1_000_000), size: clip.bounds.size)).origin)
        view.enclosingScrollView?.reflectScrolledClipView(clip)
        let last = try #require(Self.shown(view, (text as NSString).range(of: "끝 줄").location))
        #expect(last < clip.bounds.height * 0.6 && last > clip.bounds.height * 0.3, "\(last) of \(clip.bounds.height)")
    }

    /// With the editor scrolled to the note's end, its top line is half a screen or so above it. The preview, cut to
    /// its note, brought that line only as far as its own end allowed, short of the top of the screen.
    @Test func thePreviewFollowsTheEditorToTheEnd() throws {
        let body = Body(Self.filler + "\n앞 문단\n\n둘째\n\n셋째")
        let (view, _) = Self.reader(body)
        Self.trim(view)
        let line = body.text.components(separatedBy: "\n").firstIndex(of: "앞 문단")! + 1
        view.follow(line: line, frac: 0)
        let shown = try #require(Self.shown(view, (view.string as NSString).range(of: "앞 문단").location))
        #expect(abs(shown - NoteLook.margin) <= 2, "\(shown)")
    }

    @Test func theScrollerRunsTheWholeHeight() throws {
        for preview in [false, true] {
            let view: NSTextView = preview ? ReaderTextView() : SourceTextView()
            let window = Self.host(view)
            view.setFrameSize(NSSize(width: 900, height: 2000))
            let scroll = try #require(view.enclosingScrollView)
            scroll.tile()
            let scroller = try #require(scroll.verticalScroller)
            #expect(abs(scroller.frame.height - scroll.frame.height) <= 1, "\(preview): \(scroller.frame) in \(scroll.frame)")
            _ = window
        }
    }
}

/// The room past the note's end was a bottom content inset, and a long note's lower half on screen lay over it: a note
/// just opened was drawn only above it, and the clip view left clicks there to the scroll view's background.
@MainActor @Suite(.serialized)
struct NoteLowerHalfTests {
    /// A long note just opened, laid out the way the window does it rather than by hand.
    static func opened() -> (SourceTextView, NSWindow) {
        let view = SourceTextView()
        view.delegate = view
        // As `MarkdownEditor` does: the note goes into a view with no size yet, which SwiftUI sizes afterwards.
        let scroll = NoteScrollView(document: view)
        view.load(NoteScrollTests.filler)
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .latex, dark: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView!.addSubview(scroll)
        scroll.frame = window.contentView!.bounds
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        window.makeFirstResponder(view)
        return (view, window)
    }

    /// The share of the scroll view's lower half that has ink in it, as the window draws it.
    static func inkBelowTheMiddle(_ scroll: NSView) throws -> Double {
        let rep = try #require(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
        scroll.cacheDisplay(in: scroll.bounds, to: rep)
        var inked = 0, total = 0
        // Bitmap rows run top down; the lower half is the second half of them.
        for y in stride(from: rep.pixelsHigh / 2 + 8, to: rep.pixelsHigh - 8, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                total += 1
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5, color.brightnessComponent < 0.6 { inked += 1 }
            }
        }
        return Double(inked) / Double(max(1, total))
    }

    @Test func theWholeScreenIsDrawnOnOpen() throws {
        let (view, _) = Self.opened()
        let scroll = try #require(view.enclosingScrollView)
        #expect(view.frame.height > scroll.bounds.height, "the note should run past the screen")
        #expect(try Self.inkBelowTheMiddle(scroll) > 0.005)
    }

    @Test func theLowerHalfTakesClicks() throws {
        let (view, window) = Self.opened()
        for y in [40.0, 120.0, 180.0] {
            view.setSelectedRange(NSRange(location: 0, length: 0))
            let point = NSPoint(x: 450, y: y)
            #expect(window.contentView?.hitTest(point) === view, "\(y)")
            let expected = try #require(view.characterIndex(at: view.convert(point, from: nil)))
            NoteRoomPastTheEndTests.click(window, at: point)
            #expect(view.selectedRange().location > 0, "\(y)")
            #expect(abs(view.selectedRange().location - expected) <= 1, "\(y): \(view.selectedRange()) vs \(expected)")
        }
    }
}

/// The room past the note's end has no text view under it: a click there, below the middle of the
/// editor, went to the scroll view and left the caret where it was.
@MainActor @Suite(.serialized)
struct NoteRoomPastTheEndTests {
    /// A click as the window gives it: to the view under the point, with the button already up.
    static func click(_ window: NSWindow, at point: NSPoint) {
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) else { return }
        window.postEvent(up, atStart: true)
        window.contentView?.hitTest(point)?.mouseDown(with: down)
    }

    /// Clicks below a short note, left, middle and right, near the window's bottom.
    static func clicksBelow(_ view: NSTextView, in window: NSWindow) {
        NoteScrollTests.trim(view)
        view.enclosingScrollView?.tile()
        // The pointer turned to an arrow there too; the clip view shows its document cursor where the note doesn't reach.
        #expect(view.enclosingScrollView?.contentView.documentCursor === NSCursor.iBeam)
        let below = NSPoint(x: 0, y: 60)
        #expect(view.convert(below, from: nil).y > view.bounds.maxY, "the point should be past the note's end")
        let end = (view.string as NSString).length
        for x in [100.0, 450.0, 800.0] {
            view.setSelectedRange(NSRange(location: 0, length: 0))
            let point = NSPoint(x: x, y: below.y)
            #expect(window.contentView?.hitTest(point) === view, "\(x)")
            click(window, at: point)
            #expect(view.selectedRange() == NSRange(location: end, length: 0), "\(x)")
        }
    }

    @Test func aClickPastTheEditorsEndPutsTheCaretAtTheEnd() {
        let (view, window) = NoteScrollTests.source("첫 줄\n\n둘째 줄 끝")
        Self.clicksBelow(view, in: window)
    }

    @Test func aClickPastThePreviewsEndPutsTheCaretAtTheEnd() {
        let (view, window) = NoteScrollTests.reader(NoteScrollTests.Body("첫 문단\n\n둘째 문단 끝"))
        window.makeFirstResponder(view)
        Self.clicksBelow(view, in: window)
    }
}
