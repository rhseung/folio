#if os(macOS)
import AppKit
import SwiftUI

// AppKit 텍스트 뷰를 쓴다. 그래야 읽은 낱말 양옆에 알약이 채울 자리(kerning)를 주면서도, 이웃 낱말과는 온전한 공백으로 떨어뜨릴 수 있다. SwiftUI 입력란은 일반 텍스트만 받아서, 낱말보다
// 넓은 알약이 다음 낱말에 닿았다. `SourceFileEditor`처럼 kerning은 음절 사이에서만 정한다(`swaps`). 입력기 아래에서 텍스트를 바꾸면 한글 조합이 깨지기 때문이다.
struct QuickAddTextView {
    @Binding var text: String
    var prompt: String
    var marks: [QuickAddMark]
    var focusOnAppear = false
    var submit: () -> Void

    static let room: CGFloat = 4
    static let maxLines = 3
    static var font: NSFont { .systemFont(ofSize: Theme.Typeface.bodyLargeSize) }
    static var base: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = QuickAddLine.spacing
        paragraph.lineBreakStrategy = .hangulWordPriority
        return [.font: font, .foregroundColor: NSColor(Theme.Palette.text), .paragraphStyle: paragraph]
    }

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: QuickAddTextView
        var updating = false

        init(_ parent: QuickAddTextView) { self.parent = parent }

        func settled(_ view: QuickAddNSTextView) {
            QuickAddTextView.style(view, marks: parent.marks)
            if !updating, parent.text != view.string { parent.text = view.string }
        }
    }

    static func swaps(_ shown: String, for text: String, composing: Bool) -> Bool { shown != text && !composing }

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
        // 읽은 낱말 뒤에 입력한 글자는 줄을 다시 읽을 때까지 그 kerning을 지니게 된다.
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
        view.textContainerInset = NSSize(width: 0, height: QuickAddLine.overhang)
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

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let view = scroll.documentView as? NSTextView, let layout = view.layoutManager, let container = view.textContainer else {
            return nil
        }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? max(scroll.frame.width, 200)
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let line = layout.defaultLineHeight(for: Self.font)
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
        // Escape는 입력란에서처럼 popover를 닫는다. 그대로 두면 텍스트 뷰가 낱말 자동 완성 목록을 연다.
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)):
            return textView.nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: nil) ?? false
        default:
            return false
        }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        guard let text, text.contains(where: \.isNewline) else { return true }
        let joined = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        textView.insertText(joined, replacementRange: range)
        return false
    }
}
#endif
