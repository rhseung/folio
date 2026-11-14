import FolioDomain
import SwiftUI

struct SourceFileEditor {
    @Binding var text: String
    var language: String?
    @Binding var reveal: Int?
    var editable = true

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: SourceFileEditor
        var updating = false

        init(_ parent: SourceFileEditor) { self.parent = parent }

        func changed(_ string: String) {
            if !updating, parent.text != string { parent.text = string }
        }
    }

    // 바인딩은 음절이 끝나야 텍스트를 받으므로, 조합 중에는 텍스트를 바꿔 넣지 않는다. 바꿔 넣으면 입력기가 조합하던 음절이 지워지고, 입력기는 그다음 자모부터 빈칸을 사이에 두고 입력한다.
    static func swaps(_ shown: String, for text: String, composing: Bool) -> Bool { shown != text && !composing }

    static var font: PlatformFont { NoteLook.font(NoteLook.codeSize, mono: true) }

    // 파일 전체에 다시 색을 입힌다. 고친 줄만 칠하면, 그 편집이 아래쪽에서 열거나 닫는 TeX 환경이나 블록 주석의 색이 틀린다.
    @MainActor static func color(_ storage: NSTextStorage, language: String?) {
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: NoteLook.text], range: all)
        if let language {
            for token in NoteScripts.highlight(storage.string, language: language) {
                guard let look = NoteLook.token(token.classes), NSMaxRange(token.range) <= storage.length else { continue }
                storage.addAttribute(.foregroundColor, value: look.color, range: token.range)
                if look.italic {
                    storage.addAttribute(.font, value: NoteLook.font(NoteLook.codeSize, italic: true, mono: true), range: token.range)
                }
            }
        }
        storage.endEditing()
    }

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
        let scroll = makeView(context.coordinator)
        (scroll.documentView as? SourceFileTextView)?.linkOpener = context.environment.openLink
        return scroll
    }

    @MainActor func makeView(_ coordinator: Coordinator) -> NSScrollView {
        let scroll = SourceFileTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        guard let view = scroll.documentView as? SourceFileTextView else { return scroll }
        view.delegate = coordinator
        view.unmarked = { [weak coordinator, weak view] in if let view { coordinator?.settled(view) } }
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
        update(view, coordinator)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        (view as? SourceFileTextView)?.linkOpener = context.environment.openLink
        update(view, context.coordinator)
    }

    @MainActor func update(_ view: NSTextView, _ coordinator: Coordinator) {
        coordinator.parent = self
        coordinator.updating = true
        defer { coordinator.updating = false }
        view.isEditable = editable
        if Self.swaps(view.string, for: text, composing: view.hasMarkedText()) {
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
        guard let view = notification.object as? NSTextView, !view.hasMarkedText() else { return }
        settled(view)
    }

    func settled(_ view: NSTextView) {
        guard let storage = view.textStorage else { return }
        SourceFileEditor.color(storage, language: parent.language)
        changed(view.string)
    }
}

final class SourceFileTextView: NSTextView {
    var unmarked: () -> Void = {}
    var linkOpener = OpenLinkAction()

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let window, textStorage?.length ?? 0 > 0 {
            let i = characterIndex(for: window.convertPoint(toScreen: event.locationInWindow))
            if i != NSNotFound, openLink(at: i) { return }
        }
        super.mouseDown(with: event)
    }

    func openLink(at i: Int) -> Bool {
        guard let link = AppLink.link(in: string, at: i) else { return false }
        linkOpener(link)
        return true
    }

    override func unmarkText() {
        super.unmarkText()
        unmarked()
    }
}

// TeX 오류는 화면에서 줄바꿈된 행이 아니라 파일의 줄을 세므로, 파일의 줄마다 번호를 붙인다.
final class LineNumberGutter: NSRulerView {
    private weak var textView: NSTextView?
    private var observers: [NSObjectProtocol] = []

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        // macOS 14부터 뷰가 기본으로 잘라 내지 않는다. viewport는 보이는 줄 위의 줄도 배치하므로, 잘라 내지 않으면 그 번호가 페이지 막대 위에 놓인다.
        clipsToBounds = true
        let center = NotificationCenter.default
        // ruler는 텍스트가 바뀌거나 크기를 바꾼 뒤 배치가 끝나도 저절로 다시 그려지지 않는다.
        for name in [NSText.didChangeNotification, NSView.frameDidChangeNotification] {
            observers.append(
                center.addObserver(forName: name, object: textView, queue: .main) { [weak self] _ in
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

    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.textLayoutManager, let content = layout.textContentManager,
            let viewport = layout.textViewportLayoutController.viewportRange
        else { return }
        let string = textView.string as NSString
        let first = content.offset(from: content.documentRange.location, to: viewport.location)
        var line = 1
        string.enumerateSubstrings(in: NSRange(location: 0, length: min(first, string.length)), options: [.byLines, .substringNotRequired])
        { _, _, _, _ in line += 1 }
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
            label.draw(
                at: NSPoint(x: ruleThickness - Theme.Space.s - size.width, y: top + (rowHeight - size.height) / 2),
                withAttributes: attributes)
            return true
        }
    }
}
#else
extension SourceFileEditor: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
        let view = SourceFileTextView()
        view.delegate = context.coordinator
        view.unmarked = { [weak coordinator = context.coordinator, weak view] in if let view { coordinator?.settled(view) } }
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
        view.isEditable = editable
        if Self.swaps(view.text, for: text, composing: view.markedTextRange != nil) {
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
        settled(view)
    }

    func settled(_ view: UITextView) {
        let selection = view.selectedRange
        SourceFileEditor.color(view.textStorage, language: parent.language)
        view.selectedRange = selection
        changed(view.text)
    }
}

final class SourceFileTextView: UITextView {
    var unmarked: () -> Void = {}

    override func unmarkText() {
        super.unmarkText()
        unmarked()
    }
}
#endif
