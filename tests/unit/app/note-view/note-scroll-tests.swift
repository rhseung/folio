import AppKit
import FolioDomain
import Testing

@testable import Folio

// TextKit 2는 아직 배치하지 않은 글의 높이를 추정한다. 그래서 화면 위쪽에 큰 그림이 있는 노트는 변경할 때마다 줄을 제자리에 돌려놓지 않으면 화면이 튄다.
@MainActor @Suite(.serialized)
struct NoteScrollTests {
    static let filler = (1...30).map { "문단 \($0) 본문 $a_{\($0)}$ 입니다.\n\n$$\n\\sum_{k=1}^{\($0)} k^2\n$$\n" }.joined(separator: "\n")

    static func host(_ view: NSTextView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        let scroll = NoteScrollView(document: view)
        scroll.frame = window.contentView!.bounds
        window.contentView!.addSubview(scroll)
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 400)
        return window
    }

    static func fit(_ view: NSTextView) {
        view.textLayoutManager?.textViewportLayoutController.layoutViewport()
        view.setFrameSize(NSSize(width: 900, height: 8000))
    }

    static func reveal(_ view: NSTextView, _ i: Int) {
        let clip = view.enclosingScrollView!.contentView
        clip.scroll(to: NSPoint(x: 0, y: 2500))
        view.enclosingScrollView!.reflectScrolledClipView(clip)
        view.textLayoutManager?.textViewportLayoutController.layoutViewport()
        view.scrollRangeToVisible(NSRange(location: i, length: 0))
    }

    static func shown(_ view: NSTextView, _ i: Int) -> CGFloat? {
        guard let manager = view.textLayoutManager, let clip = view.enclosingScrollView?.contentView,
            let location = manager.location(manager.documentRange.location, offsetBy: i)
        else { return nil }
        manager.textViewportLayoutController.layoutViewport()
        return manager.textLayoutFragment(for: location).map { $0.layoutFragmentFrame.minY + view.textContainerOrigin.y - clip.bounds.minY }
    }

    static func source(_ text: String) -> (SourceTextView, NSWindow) {
        let view = SourceTextView()
        view.delegate = view
        let window = host(view)
        view.baseURL = NoteRender.fixtures
        view.load(text)
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .latex, dark: false)
        fit(view)
        window.makeFirstResponder(view)
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

    static func trim(_ view: NSTextView) {
        guard let manager = view.textLayoutManager else { return }
        manager.ensureLayout(for: manager.documentRange)
        view.setFrameSize(NSSize(width: 900, height: manager.usageBoundsForTextContainer.height + 2 * view.textContainerInset.height))
    }

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

    @Test func theScrollerRunsTheWholeHeight() throws {
        let view = SourceTextView()
        let window = Self.host(view)
        view.setFrameSize(NSSize(width: 900, height: 2000))
        let scroll = try #require(view.enclosingScrollView)
        // 기기의 스크롤 막대 설정과 상관없이 보이게 한다. CI에서는 스크롤 막대가 숨겨져 frame이 비어 있었다.
        scroll.autohidesScrollers = false
        scroll.tile()
        let scroller = try #require(scroll.verticalScroller)
        #expect(abs(scroller.frame.height - scroll.frame.height) <= 1, "\(scroller.frame) in \(scroll.frame)")
        _ = window
    }
}

// 노트 끝 뒤의 공간을 아래쪽 content inset으로 두었더니, 화면에 보이는 긴 노트의 아래쪽 절반이 그 inset 위에 놓였다. 그래서 막 연 노트는 inset 위쪽만 그려졌고, clip view는 그
// 자리의 클릭을 scroll view의 배경으로 넘겼다.
@MainActor @Suite(.serialized)
struct NoteLowerHalfTests {
    static func opened() -> (SourceTextView, NSWindow) {
        let view = SourceTextView()
        view.delegate = view
        let scroll = NoteScrollView(document: view)
        view.load(NoteScrollTests.filler)
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .latex, dark: false)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView!.addSubview(scroll)
        scroll.frame = window.contentView!.bounds
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        window.makeFirstResponder(view)
        return (view, window)
    }

    static func inkBelowTheMiddle(_ scroll: NSView) throws -> Double {
        let rep = try #require(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
        scroll.cacheDisplay(in: scroll.bounds, to: rep)
        var inked = 0, total = 0
        // 비트맵의 행은 위에서 아래로 이어지므로, 아래쪽 절반은 행의 뒤쪽 절반이다.
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

@MainActor @Suite(.serialized)
struct NoteRoomPastTheEndTests {
    static func click(_ window: NSWindow, at point: NSPoint) {
        guard
            let down = NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1),
            let up = NSEvent.mouseEvent(
                with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0)
        else { return }
        window.postEvent(up, atStart: true)
        window.contentView?.hitTest(point)?.mouseDown(with: down)
    }

    static func clicksBelow(_ view: NSTextView, in window: NSWindow) {
        NoteScrollTests.trim(view)
        view.enclosingScrollView?.tile()
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
}
