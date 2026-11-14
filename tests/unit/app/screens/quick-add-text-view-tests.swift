#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Folio

@MainActor @Suite(.serialized)
struct QuickAddTextViewTests {
    final class Box {
        var text = ""
        var submitted = 0
    }

    func make(_ box: Box, marks: [QuickAddMark]) -> (QuickAddTextView, QuickAddTextView.Coordinator, QuickAddNSTextView, NSWindow)? {
        let field = QuickAddTextView(text: Binding(get: { box.text }, set: { box.text = $0 }), prompt: "", marks: marks) {
            box.submitted += 1
        }
        let coordinator = field.makeCoordinator()
        let scroll = field.makeView(coordinator)
        guard let view = scroll.documentView as? QuickAddNSTextView else { return nil }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        scroll.frame = window.contentView!.bounds
        window.contentView!.addSubview(scroll)
        window.makeFirstResponder(view)
        return (field, coordinator, view, window)
    }

    @Test func aSyllableBeingComposedSurvivesTheRoomAroundReadWords() throws {
        let box = Box()
        box.text = "HW5 금"
        let marks = [QuickAddMark(range: NSRange(location: 4, length: 1), fill: .blue)]
        let (field, coordinator, view, _) = try #require(make(box, marks: marks))
        let kern = { (i: Int) in view.textStorage?.attribute(.kern, at: i, effectiveRange: nil) as? CGFloat }
        #expect(kern(3) == QuickAddTextView.room && kern(4) == QuickAddTextView.room && kern(0) == nil)

        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))
        let none = NSRange(location: NSNotFound, length: 0)
        view.setMarkedText("ㅂ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
        field.update(view, coordinator)
        #expect(view.string == "HW5 금 ㅂ" && view.hasMarkedText())
        view.setMarkedText("보", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
        field.update(view, coordinator)
        #expect(view.string == "HW5 금 보" && view.hasMarkedText())
        #expect(box.text == "HW5 금 ")
        view.insertText("보", replacementRange: none)
        view.setMarkedText("ㄱ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
        field.update(view, coordinator)
        #expect(view.string == "HW5 금 보ㄱ")
        view.unmarkText()
        #expect(box.text == "HW5 금 보ㄱ" && !view.hasMarkedText())
        #expect(kern(6) == nil)
    }

    @Test func returnAddsAndPastedLinesJoin() throws {
        let box = Box()
        let (_, _, view, _) = try #require(make(box, marks: []))
        view.insertText("HW5\n금", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.string == "HW5 금" && box.text == "HW5 금")
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(box.submitted == 1 && view.string == "HW5 금")
    }
}
#endif
