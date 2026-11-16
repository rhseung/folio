#if os(macOS)
import AppKit
import SwiftUI

final class QuickAddNSTextView: NSTextView {
    var marks: [QuickAddMark] = []
    var prompt = ""
    var unmarked: () -> Void = {}

    override func unmarkText() {
        super.unmarkText()
        unmarked()
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage else { return }
        let limit = hasMarkedText() ? markedRange().location : storage.length
        let room = QuickAddTextView.room
        let height = layout.defaultLineHeight(for: QuickAddTextView.font)
        let none = NSRange(location: NSNotFound, length: 0)
        for mark in marks where mark.range.length > 0 && NSMaxRange(mark.range) <= limit {
            let glyphs = layout.glyphRange(forCharacterRange: mark.range, actualCharacterRange: nil)
            layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: none, in: container) { line, _ in
                var pill = line.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
                pill.origin.x -= room
                pill.size.width += room
                pill.size.height = min(pill.height, height) + QuickAddLine.overhang * 2
                pill.origin.y -= QuickAddLine.overhang
                let path = NSBezierPath(roundedRect: pill, xRadius: Theme.Radius.small, yRadius: Theme.Radius.small)
                NSColor(mark.fill).setFill()
                path.fill()
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        let padding = textContainer?.lineFragmentPadding ?? 0
        let attributes: [NSAttributedString.Key: Any] = [.font: QuickAddTextView.font, .foregroundColor: NSColor.placeholderTextColor]
        (prompt as NSString).draw(at: NSPoint(x: textContainerOrigin.x + padding, y: textContainerOrigin.y), withAttributes: attributes)
    }
}
#endif
