import AppKit
import SwiftUI
import Testing

@testable import Folio

@MainActor @Suite(.serialized)
struct SourceFileEditorTests {
    @Test func aSyllableBeingComposedSurvivesTheEditorUpdating() throws {
        final class Box {
            var text = "가"
            var reveal: Int?
        }
        let box = Box()
        let editor = SourceFileEditor(
            text: Binding(get: { box.text }, set: { box.text = $0 }), language: "latex",
            reveal: Binding(get: { box.reveal }, set: { box.reveal = $0 }))
        let coordinator = editor.makeCoordinator()
        let scroll = editor.makeView(coordinator)
        let view = try #require(scroll.documentView as? SourceFileTextView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        scroll.frame = window.contentView!.bounds
        window.contentView!.addSubview(scroll)
        window.makeFirstResponder(view)

        view.setSelectedRange(NSRange(location: 1, length: 0))
        let none = NSRange(location: NSNotFound, length: 0)
        view.setMarkedText("ㄴ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
        editor.update(view, coordinator)
        #expect(view.string == "가ㄴ" && view.hasMarkedText())
        view.setMarkedText("나", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
        editor.update(view, coordinator)
        #expect(view.string == "가나")

        view.unmarkText()
        #expect(box.text == "가나")
    }
}
