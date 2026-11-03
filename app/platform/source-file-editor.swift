import SwiftUI

/// A plain-text editor for `.tex`, code and text files: monospaced, colored by the note's code highlighter. The note
/// editor's markdown styling and shortcuts would misread these files, so this is a separate, plain text view.
struct SourceFileEditor {
    @Binding var text: String
    /// The highlighter's language name; nil leaves the text uncolored.
    var language: String?
    /// Set to put the caret on a 1-based line; cleared once it's there.
    @Binding var reveal: Int?

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: SourceFileEditor
        /// Set while SwiftUI updates the view: an edit made then is the binding's own text coming in.
        var updating = false

        init(_ parent: SourceFileEditor) { self.parent = parent }

        func changed(_ string: String) {
            if !updating, parent.text != string { parent.text = string }
        }
    }

    static var font: PlatformFont { NoteLook.font(NoteLook.codeSize, mono: true) }

    /// Recolors the whole file. Highlighting only the edited line would miscolor a TeX environment or a block comment
    /// that the edit opens or closes further down.
    @MainActor static func color(_ storage: NSTextStorage, language: String?) {
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: NoteLook.text], range: all)
        if let language {
            for token in NoteScripts.highlight(storage.string, language: language) {
                guard let look = NoteLook.token(token.classes), NSMaxRange(token.range) <= storage.length else { continue }
                storage.addAttribute(.foregroundColor, value: look.color, range: token.range)
                if look.italic { storage.addAttribute(.font, value: NoteLook.font(NoteLook.codeSize, italic: true, mono: true), range: token.range) }
            }
        }
        storage.endEditing()
    }

    /// The text range of a 1-based line, empty at its start.
    static func start(ofLine line: Int, in string: String) -> NSRange {
        let ns = string as NSString
        var location = 0
        for _ in 1..<max(1, line) {
            let next = ns.range(of: "\n", options: [], range: NSRange(location: location, length: ns.length - location))
            guard next.location != NSNotFound else { break }
            location = NSMaxRange(next)
        }
        return NSRange(location: location, length: 0)
    }
}

#if os(macOS)
extension SourceFileEditor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.smartInsertDeleteEnabled = false
        view.textContainerInset = NSSize(width: Theme.Space.s, height: Theme.Space.l)
        view.typingAttributes = [.font: Self.font, .foregroundColor: NoteLook.text]
        view.string = text
        if let storage = view.textStorage { Self.color(storage, language: language) }
        let gutter = LineNumberGutter(textView: view)
        scroll.verticalRulerView = gutter
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        update(view, context.coordinator)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        update(view, context.coordinator)
    }

    @MainActor private func update(_ view: NSTextView, _ coordinator: Coordinator) {
        coordinator.parent = self
        coordinator.updating = true
        defer { coordinator.updating = false }
        if view.string != text {
            view.string = text
            if let storage = view.textStorage { Self.color(storage, language: language) }
        }
        if let reveal {
            let range = Self.start(ofLine: reveal, in: view.string)
            view.setSelectedRange(range)
            view.scrollRangeToVisible(range)
            view.window?.makeFirstResponder(view)
            DispatchQueue.main.async { self.reveal = nil }
        }
    }
}

extension SourceFileEditor.Coordinator: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let view = notification.object as? NSTextView, !view.hasMarkedText(), let storage = view.textStorage else { return }
        SourceFileEditor.color(storage, language: parent.language)
        changed(view.string)
    }
}

/// Numbers each line of the file, not each wrapped row, since that is what TeX's errors count.
final class LineNumberGutter: NSRulerView {
    private weak var textView: NSTextView?
    private var observers: [NSObjectProtocol] = []

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        // Views stopped clipping by default in macOS 14; the viewport lays out lines above the visible ones, and
        // their numbers would otherwise land on the page bar.
        clipsToBounds = true
        let center = NotificationCenter.default
        // A ruler isn't redrawn on its own when the text changes or the layout settles after a resize.
        for name in [NSText.didChangeNotification, NSView.frameDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: textView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private var font: NSFont { NoteLook.font(NoteLook.smallSize, mono: true) }

    private func refresh() {
        let lines = (textView?.string ?? "").reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        let digits = String(max(lines, 99)).count
        let width = ceil(("0" as NSString).size(withAttributes: [.font: font]).width * CGFloat(digits)) + Theme.Space.l * 2
        if ruleThickness != width { ruleThickness = width }
        needsDisplay = true
    }

    // No ruler background or baseline: the gutter sits on the editor's own card.
    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.textLayoutManager, let content = layout.textContentManager,
              let viewport = layout.textViewportLayoutController.viewportRange else { return }
        let string = textView.string as NSString
        let first = content.offset(from: content.documentRange.location, to: viewport.location)
        // The viewport starts at a paragraph, so every line before it ends with a newline inside this range.
        var line = 1
        string.enumerateSubstrings(in: NSRange(location: 0, length: min(first, string.length)), options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NoteLook.text3]
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect
        layout.enumerateTextLayoutFragments(from: viewport.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard frame.minY <= visible.maxY else { return false }
            defer { line += 1 }
            guard frame.maxY >= visible.minY else { return true }
            let row = fragment.textLineFragments.first
            let rowHeight = row?.typographicBounds.height ?? frame.height
            let label = String(line) as NSString
            let size = label.size(withAttributes: attributes)
            let top = convert(NSPoint(x: 0, y: frame.minY + origin.y), from: textView).y
            label.draw(at: NSPoint(x: ruleThickness - Theme.Space.s - size.width, y: top + (rowHeight - size.height) / 2), withAttributes: attributes)
            return true
        }
    }
}
#else
extension SourceFileEditor: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.spellCheckingType = .no
        view.textContainerInset = UIEdgeInsets(top: Theme.Space.l, left: Theme.Space.l, bottom: Theme.Space.l, right: Theme.Space.l)
        view.typingAttributes = [.font: Self.font, .foregroundColor: NoteLook.text]
        view.text = text
        Self.color(view.textStorage, language: language)
        update(view, context.coordinator)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        update(view, context.coordinator)
    }

    @MainActor private func update(_ view: UITextView, _ coordinator: Coordinator) {
        coordinator.parent = self
        coordinator.updating = true
        defer { coordinator.updating = false }
        if view.text != text {
            view.text = text
            Self.color(view.textStorage, language: language)
        }
        if let reveal {
            let range = Self.start(ofLine: reveal, in: view.text)
            view.selectedRange = range
            view.scrollRangeToVisible(range)
            view.becomeFirstResponder()
            DispatchQueue.main.async { self.reveal = nil }
        }
    }
}

extension SourceFileEditor.Coordinator: UITextViewDelegate {
    func textViewDidChange(_ view: UITextView) {
        guard view.markedTextRange == nil else { return }
        let selection = view.selectedRange
        SourceFileEditor.color(view.textStorage, language: parent.language)
        view.selectedRange = selection
        changed(view.text)
    }
}
#endif
