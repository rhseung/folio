#if os(macOS)
import AppKit
import SwiftUI

struct QuickAddMark: Equatable {
    var range: NSRange
    var fill: Color
}

/// The quick add line on the Mac: an AppKit text view, so a word the line read can get room on both sides (kerning)
/// for its pill to fill while a full space still parts it from its neighbor. A SwiftUI field takes only plain text,
/// and a pill wider than its word ran into the next one. The kerning is set only between syllables (`swaps`), as in
/// `SourceFileEditor`: changing the text under the input method breaks Korean composition.
struct QuickAddTextView {
    @Binding var text: String
    var prompt: String
    var marks: [QuickAddMark]
    /// Takes the keyboard when it appears, as in the toolbar's popover.
    var focusOnAppear = false
    var submit: () -> Void

    /// Room each read word gets on either side, and how far its pill reaches into it: equal, so the pill has this
    /// much inside its edge and the space beyond it stays whole.
    static let room: CGFloat = 4
    static let maxLines = 3
    static var font: NSFont { .systemFont(ofSize: Theme.Typeface.bodyLargeSize) }
    static var base: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = QuickAddLine.spacing
        // Korean wraps between words as in the rest of the app, not mid-word as AppKit's default does.
        paragraph.lineBreakStrategy = .hangulWordPriority
        return [.font: font, .foregroundColor: NSColor(Theme.Palette.text), .paragraphStyle: paragraph]
    }

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: QuickAddTextView
        /// Set while SwiftUI updates the view: an edit made then is the binding's own text coming in.
        var updating = false

        init(_ parent: QuickAddTextView) { self.parent = parent }

        func settled(_ view: QuickAddNSTextView) {
            QuickAddTextView.style(view, marks: parent.marks)
            if !updating, parent.text != view.string { parent.text = view.string }
        }
    }

    /// The binding's text replaces the view's only once a syllable is done, so it isn't swapped in while one is composed.
    static func swaps(_ shown: String, for text: String, composing: Bool) -> Bool { shown != text && !composing }

    /// The plain look over the whole line, then the room around each read word: kerning on the letter before it
    /// (the space) and on its own last letter.
    @MainActor static func style(_ view: QuickAddNSTextView, marks: [QuickAddMark]) {
        view.marks = marks
        view.needsDisplay = true
        guard !view.hasMarkedText(), let storage = view.textStorage else { return }
        let length = storage.length
        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: length))
        for mark in marks where mark.range.length > 0 && NSMaxRange(mark.range) <= length {
            if mark.range.location > 0 {
                storage.addAttribute(.kern, value: room, range: NSRange(location: mark.range.location - 1, length: 1))
            }
            storage.addAttribute(.kern, value: room, range: NSRange(location: NSMaxRange(mark.range) - 1, length: 1))
        }
        storage.endEditing()
        // A letter typed after a read word would carry its kerning until the line is read again.
        view.typingAttributes = base
    }
}

extension QuickAddTextView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView { makeView(context.coordinator) }

    @MainActor func makeView(_ coordinator: Coordinator) -> NSScrollView {
        let view = QuickAddNSTextView(usingTextLayoutManager: false)
        view.delegate = coordinator
        view.unmarked = { [weak coordinator, weak view] in if let view { coordinator?.settled(view) } }
        view.prompt = prompt
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.smartInsertDeleteEnabled = false
        // The first row's pill reaches above the text, and the last row's below it.
        view.textContainerInset = NSSize(width: 0, height: QuickAddLine.overhang)
        // The room a pill needs before a word at the line's start, which would otherwise be cut off at the edge.
        view.textContainer?.lineFragmentPadding = Self.room
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.typingAttributes = Self.base
        view.string = text
        Self.style(view, marks: marks)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        view.frame = NSRect(origin: .zero, size: scroll.contentSize)
        scroll.documentView = view
        if focusOnAppear {
            DispatchQueue.main.async { [weak view] in
                if let view { view.window?.makeFirstResponder(view) }
            }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? QuickAddNSTextView else { return }
        update(view, context.coordinator)
    }

    @MainActor func update(_ view: QuickAddNSTextView, _ coordinator: Coordinator) {
        coordinator.parent = self
        coordinator.updating = true
        defer { coordinator.updating = false }
        view.prompt = prompt
        if Self.swaps(view.string, for: text, composing: view.hasMarkedText()) {
            view.string = text
        }
        if view.marks != marks || !view.hasMarkedText() { Self.style(view, marks: marks) }
    }

    /// As tall as its lines up to three; past that it scrolls.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let view = scroll.documentView as? NSTextView, let layout = view.layoutManager, let container = view.textContainer else {
            return nil
        }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? max(scroll.frame.width, 200)
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let line = layout.defaultLineHeight(for: Self.font)
        // TextKit puts the spacing after every row but the last, so three rows are three lines and two spacings.
        let most = line * CGFloat(Self.maxLines) + QuickAddLine.spacing * CGFloat(Self.maxLines - 1)
        let used = layout.usedRect(for: container).height
        return CGSize(width: width, height: ceil(min(max(used, line), most)) + QuickAddLine.overhang * 2)
    }
}

extension QuickAddTextView.Coordinator: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let view = notification.object as? QuickAddNSTextView, !view.hasMarkedText() else { return }
        settled(view)
    }

    /// Return adds; Tab moves on. The line is one line that wraps, so neither goes into it.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            if !textView.hasMarkedText() { parent.submit() }
            return true
        case #selector(NSResponder.insertTab(_:)):
            textView.window?.selectNextKeyView(nil)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            textView.window?.selectPreviousKeyView(nil)
            return true
        // Escape closes the popover as it does from a field; a text view would open its word completion list instead.
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)):
            return textView.nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: nil) ?? false
        default:
            return false
        }
    }

    /// Pasted lines join into the one line.
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        guard let text, text.contains(where: \.isNewline) else { return true }
        let joined = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        textView.insertText(joined, replacementRange: range)
        return false
    }
}

final class QuickAddNSTextView: NSTextView {
    var marks: [QuickAddMark] = []
    var prompt = ""
    var unmarked: () -> Void = {}

    // A syllable ended without a keystroke (a click elsewhere, another app) changes no text, so no `textDidChange`
    // hands it to the binding.
    override func unmarkText() {
        super.unmarkText()
        unmarked()
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage else { return }
        // While a syllable is composed the marks were read from the text before it, so only those ahead of it hold.
        let limit = hasMarkedText() ? markedRange().location : storage.length
        let room = QuickAddTextView.room
        let height = layout.defaultLineHeight(for: QuickAddTextView.font)
        let none = NSRange(location: NSNotFound, length: 0)
        for mark in marks where mark.range.length > 0 && NSMaxRange(mark.range) <= limit {
            let glyphs = layout.glyphRange(forCharacterRange: mark.range, actualCharacterRange: nil)
            layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: none, in: container) { line, _ in
                // The line's rect ends after the last letter's kerning; the pill reaches `room` past each edge of the
                // letters, which is as far as the kerning on either side.
                var pill = line.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
                pill.origin.x -= room
                pill.size.width += room
                // A row's rect takes in the spacing below it; the pill covers only the letters' line.
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
