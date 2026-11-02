import FolioDomain
import SwiftUI

/// The read view: the note rendered by `ReaderBuilder` in a TextKit 2 text view. With `edit` set, paragraphs, headings
/// and lists that write back exactly as they're written can be typed into (`ReaderCore`).
struct NoteReader {
    var text: String
    var baseURL: URL?
    var math: MathSyntax = .latex
    var openNote: (String) -> Void = { _ in }
    /// Called with a block's body lines, the text they should still hold and their new text; false when they no
    /// longer hold it, and the note is shown anew.
    var edit: (@MainActor (_ from: Int, _ to: Int, _ old: String, _ new: String) -> Bool)?
    /// Set beside the editor: the view follows the editor's scroll.
    var link: PreviewLink?
    /// What ⌘E does while the view has the keyboard.
    var toggleMode: (@MainActor () -> Void)?

    @MainActor func update(_ view: ReaderTextView, accent: CourseAccent, dark: Bool) {
        view.baseURL = baseURL
        view.openNote = openNote
        view.edit = edit
        view.toggleMode = toggleMode
        link?.view = view
        view.link = link
        view.configure(accent: accent, syntax: math, dark: dark)
        view.show(text)
    }
}

/// Carries the editor's scroll to the preview beside it. Not observed state: going through SwiftUI would render the
/// note again on every step of a scroll.
@MainActor final class PreviewLink {
    weak var view: ReaderTextView?
    private(set) var last: (line: Int, frac: Double)?

    func follow(line: Int, frac: Double) {
        last = (line, frac)
        refollow()
    }

    func refollow() {
        guard let last else { return }
        view?.follow(line: last.line, frac: last.frac)
    }
}

#if os(macOS)
extension NoteReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let view = ReaderTextView()
        update(view, accent: context.environment.accent, dark: context.environment.colorScheme == .dark)
        return NoteScrollView(document: view)
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? ReaderTextView else { return }
        update(view, accent: context.environment.accent, dark: context.environment.colorScheme == .dark)
    }
}

final class ReaderTextView: NoteTextView, NSTextViewDelegate {
    private(set) var core: ReaderCore!
    var edit: (@MainActor (Int, Int, String, String) -> Bool)? {
        get { core.edit }
        set { core.edit = newValue; isEditable = newValue != nil }
    }
    var toggleMode: (@MainActor () -> Void)?
    weak var link: PreviewLink?
    var blocks: [ReaderBlock] { core.blocks }
    /// Set while the view changes its own text, which the edit rules would refuse.
    private var internalChange = false
    /// Where a click changed the page (a box, a callout's fold): it stays under the pointer.
    private var clicked: Int?

    override init() {
        super.init()
        isRichText = true
        isEditable = false
        delegate = self
        core = ReaderCore(storage: textStorage!)
        core.rendered = { [weak self] in self?.rendered() }
        core.replacing = { [weak self] swap in
            guard let self, let at = self.clicked ?? self.firstVisible, let y = self.screenY(of: at) else { return swap() }
            swap()
            self.place(at, at: y)
        }
        shortcut = { [weak self] key in self?.key(key) ?? false }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(accent: CourseAccent, syntax: MathSyntax, dark: Bool) {
        accentColors(accent)
        core.configure(accent: accent, syntax: syntax, baseURL: baseURL, dark: dark, width: columnWidth)
    }

    override func columnChanged() {
        core.builder?.width = columnWidth
        core.rerender()
    }

    private var typing: Bool { window?.firstResponder === self && edit != nil }

    func show(_ text: String) { core.show(text, typing: typing) }

    override func layout() {
        super.layout()
        placeViews()
    }

    override func prepareContent(in rect: NSRect) {
        super.prepareContent(in: rect)
        placeViews()
    }

    private func placeViews() {
        guard let manager = textLayoutManager else { return }
        AttachedViews.place(in: self, storage: core.storage, manager: manager, origin: textContainerOrigin)
    }

    private func rendered() {
        placeViews()
        undoManager?.removeAllActions(withTarget: self)
        setSelectedRange(NSRange(location: min(selectedRange().location, core.storage.length), length: 0))
        // Beside the editor the page follows it, except right after a click here, which leaves the editor still.
        if clicked == nil { link?.refollow() }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { core.leave() }
        return resigned
    }

    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        if internalChange { return super.shouldChangeText(in: range, replacementString: replacementString) }
        guard let b = core.editableBlock(for: range), super.shouldChangeText(in: range, replacementString: replacementString) else { return false }
        core.dirty = b
        return true
    }

    func textDidChange(_ notification: Notification) { core.changed() }

    func textViewDidChangeSelection(_ notification: Notification) {
        if let attributes = core.typingAttributes(at: selectedRange().location) { typingAttributes = attributes }
    }

    private func apply(_ change: ReaderCore.Change) {
        internalChange = true
        defer { internalChange = false }
        guard shouldChangeText(in: change.range, replacementString: change.text.string) else { return }
        core.storage.replaceCharacters(in: change.range, with: change.text)
        didChangeText()
        setSelectedRange(NSRange(location: change.caret, length: 0))
    }

    // MARK: Keys

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText() else { return super.insertNewline(sender) }
        if let change = core.newline(selectedRange()) { apply(change) }
    }

    override func insertLineBreak(_ sender: Any?) { insertText("\u{2028}", replacementRange: selectedRange()) }

    override func insertParagraphSeparator(_ sender: Any?) { insertNewline(sender) }

    override func deleteBackward(_ sender: Any?) {
        if let change = core.backspace(selectedRange()) { return apply(change) }
        super.deleteBackward(sender)
    }

    private func key(_ key: Character) -> Bool {
        switch key {
        case "b": toggle(.strong)
        case "i": toggle(.emphasis)
        case "e": toggleMode?()
        default: return false
        }
        return true
    }

    private func toggle(_ mark: InlineMarks) {
        if selectedRange().length == 0 {
            typingAttributes = ReaderCore.toggled(mark, typingAttributes)
        } else if core.toggle(mark, in: selectedRange()) {
            needsDisplay = true
        }
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    // MARK: Clicks

    override func mouseDown(with event: NSEvent) {
        guard let i = characterIndex(at: convert(event.locationInWindow, from: nil)) else { return super.mouseDown(with: event) }
        if openLink(at: i, event: event) { return }
        guard event.modifierFlags.intersection([.command, .shift, .option]).isEmpty, event.clickCount == 1, click(at: i) else { return super.mouseDown(with: event) }
    }

    /// A plain click at `i` that ticks a box, folds a callout or opens a link; false where it places the caret.
    func click(at i: Int) -> Bool {
        clicked = i
        defer { clicked = nil }
        guard let tap = core.tap(at: i, opensLinks: false) else { return false }
        switch tap {
        case .change(let change):
            apply(change)
            core.commit()
        case .open(let wiki, let href):
            if let wiki { openNote(wiki) } else if let href { NoteLinks.open(href, base: baseURL, openNote: openNote) }
        case .handled:
            break
        }
        return true
    }

    // MARK: Following the editor

    func follow(line: Int, frac: Double) {
        guard !typing, let scroll = enclosingScrollView, let manager = textLayoutManager else { return }
        let y = max(0, textContainerOrigin.y + core.follow(line: line, frac: frac) { manager.top(of: $0) } - NoteLook.margin)
        let clip = scroll.contentView
        // Bounded as a scroll by hand is, so the room past the note's end counts.
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: NSPoint(x: 0, y: y), size: clip.bounds.size)).origin)
        scroll.reflectScrolledClipView(clip)
    }
}
#else
extension NoteReader: UIViewRepresentable {
    func makeUIView(context: Context) -> ReaderTextView {
        let view = ReaderTextView()
        update(view, accent: context.environment.accent, dark: context.environment.colorScheme == .dark)
        return view
    }

    func updateUIView(_ view: ReaderTextView, context: Context) {
        update(view, accent: context.environment.accent, dark: context.environment.colorScheme == .dark)
    }
}

final class ReaderTextView: NoteTextView, UITextViewDelegate, UIGestureRecognizerDelegate {
    private(set) var core: ReaderCore!
    var edit: (@MainActor (Int, Int, String, String) -> Bool)? {
        get { core.edit }
        set { core.edit = newValue; isEditable = newValue != nil }
    }
    var toggleMode: (@MainActor () -> Void)?
    weak var link: PreviewLink?
    var blocks: [ReaderBlock] { core.blocks }
    private var internalChange = false

    override init() {
        super.init()
        isEditable = false
        delegate = self
        core = ReaderCore(storage: textStorage)
        core.rendered = { [weak self] in self?.rendered() }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(accent: CourseAccent, syntax: MathSyntax, dark: Bool) {
        accentColors(accent)
        core.configure(accent: accent, syntax: syntax, baseURL: baseURL, dark: dark, width: columnWidth)
    }

    override func columnChanged() {
        core.builder?.width = columnWidth
        core.rerender()
    }

    private var typing: Bool { isFirstResponder && edit != nil }

    func show(_ text: String) { core.show(text, typing: typing) }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeViews()
    }

    private func placeViews() {
        guard let manager = textLayoutManager else { return }
        AttachedViews.place(in: self, storage: core.storage, manager: manager, origin: CGPoint(x: textContainerInset.left, y: textContainerInset.top))
    }

    private func rendered() {
        placeViews()
        undoManager?.removeAllActions()
        link?.refollow()
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { core.leave() }
        return resigned
    }

    private func apply(_ change: ReaderCore.Change) {
        internalChange = true
        defer { internalChange = false }
        core.storage.replaceCharacters(in: change.range, with: change.text)
        selectedRange = NSRange(location: change.caret, length: 0)
        core.changed()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if internalChange || markedTextRange != nil { return true }
        if text == "\n" {
            if let change = core.newline(range) { apply(change) }
            return false
        }
        if text.isEmpty, range.length == 1, selectedRange.length == 0, let change = core.backspace(NSRange(location: NSMaxRange(range), length: 0)) {
            apply(change)
            return false
        }
        guard let b = core.editableBlock(for: range) else { return false }
        core.dirty = b
        return true
    }

    func textViewDidChange(_ textView: UITextView) { core.changed() }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if let attributes = core.typingAttributes(at: selectedRange.location) { typingAttributes = attributes }
    }

    override func toggleBoldface(_ sender: Any?) { toggle(.strong) }
    override func toggleItalics(_ sender: Any?) { toggle(.emphasis) }

    private func toggle(_ mark: InlineMarks) {
        if selectedRange.length == 0 {
            typingAttributes = ReaderCore.toggled(mark, typingAttributes)
        } else {
            _ = core.toggle(mark, in: selectedRange)
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// A tap opens a link even where text is typed: there's no ⌘ to hold on a touch screen.
    @objc private func tapped(_ g: UITapGestureRecognizer) {
        guard let i = characterIndex(at: g.location(in: self)), let tap = core.tap(at: i, opensLinks: true) else { return }
        switch tap {
        case .change(let change):
            apply(change)
            core.commit()
        case .open(let wiki, let href):
            if let wiki { openNote(wiki) } else if let href { NoteLinks.open(href, base: baseURL, openNote: openNote) }
        case .handled:
            break
        }
    }

    func follow(line: Int, frac: Double) {
        guard !typing, let manager = textLayoutManager else { return }
        let y = textContainerInset.top + core.follow(line: line, frac: frac) { manager.top(of: $0) } - NoteLook.margin
        setContentOffset(CGPoint(x: 0, y: max(0, min(y, contentSize.height - bounds.height + contentInset.bottom))), animated: false)
    }
}
#endif
