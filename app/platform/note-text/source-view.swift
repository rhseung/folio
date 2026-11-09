import FolioDomain
import FolioMarkdown
import SwiftUI

/// The write view: the note's markdown source in a TextKit 2 text view, styled in place by `SourceStyler`.
struct MarkdownEditor {
    @Binding var text: String
    var baseURL: URL?
    var math: MathSyntax
    /// Set to insert at the cursor; cleared once inserted.
    @Binding var insert: String?
    /// Saves a dropped or pasted file and returns the markdown that links it, or nil when it couldn't be saved.
    var saveFile: (String, Data) -> String?
    var openNote: (String) -> Void
    /// The editor's top line and how far into it the view is scrolled, for a preview to follow.
    var onScroll: @MainActor (Int, Double) -> Void = { _, _ in }
    var assist = NoteAssist()
    /// Where a link opened the note at: the caret goes to that heading or block once for each new one.
    var anchor: AppLink.Anchor?
    /// The notes block references' cards draw from, as the preview's; without it references show none.
    var embeds: NoteEmbedSource?
    /// The workspace's `notesRevision`.
    var revision = 0
    /// Set to put a symbol picked in the math palette at the cursor; cleared once inserted.
    var insertMath: Binding<CompletionItem?> = .constant(nil)
    /// Opens the input guide for this note (#395): the `/` menu's last item and 도움말 › 입력 안내 come here.
    var openGuide: @MainActor () -> Void = {}
    /// The screen's handle on this view, for the outline beside it.
    var views: NoteViews?

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: MarkdownEditor
        weak var view: SourceTextView?
        /// Set while SwiftUI updates the view: an edit made then is the binding's own text coming in.
        var updating = false
        var revealed: AppLink.Anchor?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func changed() {
            guard let view, !view.hasMarkedText() else { return }
            if !updating, parent.text != view.string { parent.text = view.string }
        }
    }

    @MainActor func update(_ view: SourceTextView, _ coordinator: Coordinator, accent: CourseAccent, dark: Bool, openLink: OpenLinkAction = OpenLinkAction()) {
        coordinator.parent = self
        coordinator.updating = true
        defer { coordinator.updating = false }
        view.baseURL = baseURL
        view.saveFile = saveFile
        view.openNote = openNote
        view.linkOpener = openLink
        view.linkName = embeds?.name ?? { _ in nil }
        view.onScroll = onScroll
        view.openGuide = openGuide
        if views?.editor !== view { views?.editor = view }
        view.configure(accent: accent, syntax: math, dark: dark)
        view.setAssist(assist, syntax: math)
        #if os(macOS)
        // The iPad's card comes on a long press, left for later (#35).
        view.cards = embeds
        view.cardsRevision = revision
        #endif
        // The binding hasn't the syllable being composed yet, so swapping the text in then would delete it under the
        // input method, which then types each next jamo over a gap.
        if view.string != text, !view.hasMarkedText() { view.replace(with: text) }
        // Not before the note's text has come in: the model loads it after the view is made, and an anchor looked for
        // in the empty text would be given up on.
        // Cleared with no anchor, as the preview does: back to the note without one and forward to the anchor again
        // moves the caret again.
        if anchor == nil { coordinator.revealed = nil }
        if let anchor, anchor != coordinator.revealed, !text.isEmpty, view.string == text {
            coordinator.revealed = anchor
            if let location = anchor.location(in: text) { view.reveal(location) }
        }
        if let insert {
            view.insertAtCaret(insert)
            DispatchQueue.main.async { self.insert = nil }
        }
        // Put in after the update: an edit made during it doesn't reach the binding (`updating`), and the next update
        // would swap the text back. Checked again there, so an update run twice before it inserts once.
        if insertMath.wrappedValue != nil {
            DispatchQueue.main.async {
                guard let item = self.insertMath.wrappedValue else { return }
                self.insertMath.wrappedValue = nil
                view.insertMath(item)
            }
        }
    }
}

/// Room past the note's end: the editor's last line comes up to the middle of the screen, since one writes at the end.
/// The preview has room of its own (web/src/note.css), to bring its last block up to the top.
enum NoteOverscroll {
    static func bottom(_ height: CGFloat) -> CGFloat { (height / 2).rounded() }
}

/// A `folio://` address pasted into a note goes in as a link to what it names, as link completion writes one (#43):
/// `[[material:<ID>#page=2|05_Matchings.pdf]]`. Nil pastes it as text: it is something else, or it lands inside a
/// link being written (whose target it then is), code or math.
func pastedNoteLink(_ pasted: String?, into text: String, at caret: Int, name: (AppLink) -> String?) -> String? {
    guard let pasted = pasted?.trimmingCharacters(in: .whitespacesAndNewlines), let link = AppLink(string: pasted),
          WikiLink.pastesAsLink(in: text as NSString, at: caret) else { return nil }
    return link.noteLink(named: name(link))
}

#if os(macOS)
extension MarkdownEditor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let view = SourceTextView()
        view.delegate = view
        view.onChange = { [weak coordinator = context.coordinator] in coordinator?.changed() }
        context.coordinator.view = view
        let scroll = NoteScrollView(document: view)
        view.load(text)
        update(view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
               openLink: context.environment.openLink)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? SourceTextView else { return }
        update(view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
               openLink: context.environment.openLink)
    }
}

/// A scroll view holding a note view, with the find bar above it.
final class NoteScrollView: NSScrollView {
    init(document: NSTextView) {
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = false
        borderType = .noBorder
        contentView = NoteClipView()
        findBarPosition = .aboveContent
        document.minSize = .zero
        document.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        document.isVerticallyResizable = true
        document.isHorizontallyResizable = false
        document.autoresizingMask = [.width]
        documentView = document
        contentView.postsBoundsChangedNotifications = true
        automaticallyAdjustsContentInsets = false
        // The text view sets the I-beam only over itself, and the room past the note's end lies outside it.
        documentCursor = .iBeam
    }

    required init?(coder: NSCoder) { fatalError() }

    // Every click over the note is routed here, whatever AppKit's own hit test gave: with a plain clip view the scroll
    // view took clicks over its document itself, and with `NoteClipView` it hands back the deepest view instead. A view
    // the note puts over its text (the preview bubble) takes no clicks. The room past the note's end is the clip
    // view's, under no part of the note; a click there went nowhere, so the note takes it and puts the caret at its end.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard let hit, let document = documentView, hit === self || hit === contentView || hit.isDescendant(of: document) else { return hit }
        return document
    }
}

/// The room past the note's end, as more document to scroll through. As a bottom content inset it was a strip the clip
/// view leaves to the scroll view: clicks there went to the scroll view's background, even over text, and a note just
/// opened was drawn only down to it, so the lower half of the screen stayed blank until a scroll and never took a click.
final class NoteClipView: NSClipView {
    override var documentRect: NSRect {
        var rect = super.documentRect
        guard let document = documentView else { return rect }
        let room = NoteOverscroll.bottom(bounds.height)
        rect.size.height = max(rect.height, document.frame.height + room)
        return rect
    }
}

/// A TextKit 2 text view for notes: the column centered at the note measure, and the note's own clicks (⌘ on a link, a
/// task's box) taken before the text view's. It draws only styled text, as TextKit lays it out.
///
/// The system text views, not a package such as STTextView: that one is AppKit-first with its UIKit port still young,
/// and Hangul composition, which the system views get right and `NoteHangulTests` guard, is where editors break.
class NoteTextView: NSTextView {
    private let content = NSTextContentStorage()
    var baseURL: URL?
    var openNote: (String) -> Void = { _ in }
    var linkOpener = OpenLinkAction()
    /// Names what a pasted `folio://` address points at (`NoteEmbedSource.name`).
    var linkName: (AppLink) -> String? = { _ in nil }
    /// The note's shortcuts, taken by key code so the Korean input source doesn't change them.
    var shortcut: ((Character) -> Bool)?
    private var caretObserver: NSObjectProtocol?
    static let letters: [UInt16: Character] = [11: "b", 34: "i", 14: "e"]

    init() {
        let manager = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        manager.textContainer = container
        content.addTextLayoutManager(manager)
        super.init(frame: .zero, textContainer: container)
        drawsBackground = false
        allowsUndo = true
        isRichText = false
        importsGraphics = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        textContainerInset = NSSize(width: NoteLook.margin, height: NoteLook.margin)
    }

    required init?(coder: NSCoder) { fatalError() }

    override init(frame: NSRect, textContainer: NSTextContainer?) { fatalError() }

    /// The text column's width, which the bubble's pictures fit.
    var columnWidth: CGFloat { max(120, min(NoteLook.measure, bounds.width) - 2 * NoteLook.margin) }

    func accentColors(_ accent: CourseAccent) {
        insertionPointColor = accent.native
        selectedTextAttributes = [.backgroundColor: accent.native.withAlphaComponent(0.24)]
    }

    override func setFrameSize(_ size: NSSize) {
        let column = columnWidth
        super.setFrameSize(size)
        let inset = max(NoteLook.margin, (size.width - NoteLook.measure) / 2 + NoteLook.margin)
        if textContainerInset.width != inset { textContainerInset = NSSize(width: inset, height: NoteLook.margin) }
        if columnWidth != column { columnChanged() }
    }

    func columnChanged() {}

    // AppKit sizes its `NSTextInsertionIndicator` to the whole line, more than once per move and with no hook, so it's
    // refitted whenever its frame changes.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard let indicator = subview as? NSTextInsertionIndicator else { return }
        indicator.postsFrameChangedNotifications = true
        if let caretObserver { NotificationCenter.default.removeObserver(caretObserver) }
        caretObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: indicator, queue: nil) { [weak self, weak indicator] _ in
            MainActor.assumeIsolated {
                guard let self, let indicator, let storage = self.textStorage else { return }
                let fitted = NoteLines.caret(indicator.frame, at: self.selectedRange().location, in: storage)
                if fitted != indicator.frame { indicator.frame = fitted }
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let key = Self.letters[event.keyCode], shortcut?(key) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func characterIndex(at point: NSPoint) -> Int? {
        guard let window, let storage = textStorage, storage.length > 0 else { return nil }
        let i = characterIndex(for: window.convertPoint(toScreen: convert(point, to: nil)))
        return i == NSNotFound || i >= storage.length ? nil : i
    }

    /// ⌘-click opens a link; a plain click places the caret, as anywhere else in the text.
    func openLink(at i: Int, event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), let storage = textStorage else { return false }
        let attributes = storage.attributes(at: i, effectiveRange: nil)
        if attributes[.noteWiki] is String {
            if let found = wikiLink(at: i) { NoteLinks.open(found.link.href, base: nil, openNote: openNote, openLink: linkOpener) }
            return true
        }
        if let href = attributes[.noteHref] as? String {
            NoteLinks.open(href, base: baseURL, openNote: openNote, openLink: linkOpener)
            return true
        }
        // A bare folio:// address, which markdown doesn't make a link of.
        if let found = AppLink.link(in: storage.string, at: i) {
            linkOpener(found)
            return true
        }
        return false
    }

    /// The wikilink the character at `i` is in. The attribute holds the target alone, so the link (with the page or
    /// block of `[[material:…#page=12]]`) is read from the line; and from the line rather than the attribute's run,
    /// since the brackets and an ID are styled apart from the name and the run under the pointer is only part of it.
    func wikiLink(at i: Int) -> (link: WikiLink, range: NSRange)? {
        guard let storage = textStorage, i < storage.length, storage.attribute(.noteWiki, at: i, effectiveRange: nil) is String else { return nil }
        let text = storage.string as NSString
        let line = text.paragraphRange(for: NSRange(location: i, length: 0))
        let written = text.substring(with: line)
        guard let m = written.matches(of: WikiLink.pattern).first(where: { NSRange($0.range, in: written).contains(i - line.location) }) else { return nil }
        let r = NSRange(m.range, in: written)
        return (WikiLink(m), NSRange(location: line.location + r.location, length: r.length))
    }

    /// The first line of the view's top and how far into it the view is scrolled.
    func topLine(lineStarts: [Int]) -> (line: Int, frac: Double) {
        guard let manager = textLayoutManager else { return (1, 0) }
        let y = max(0, visibleRect.minY - textContainerOrigin.y)
        guard let fragment = manager.textLayoutFragment(for: CGPoint(x: 0, y: y)) else { return (1, 0) }
        let offset = manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location)
        let line = (lineStarts.lastIndex { $0 <= offset } ?? 0) + 1
        let frame = fragment.layoutFragmentFrame
        return (line, frame.height > 0 ? min(1, max(0, (y - frame.minY) / frame.height)) : 0)
    }

    // MARK: Keeping the place

    // TextKit 2 guesses the height of text it hasn't laid out, so after the text or its look changes the same scroll
    // offset shows other text. Every change notes where a line stood on screen and puts it back there afterwards.

    /// The first character on the top line of the screen.
    var firstVisible: Int? {
        guard let manager = textLayoutManager,
              let fragment = manager.textLayoutFragment(for: CGPoint(x: 0, y: max(0, visibleRect.minY - textContainerOrigin.y))) else { return nil }
        return manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location)
    }

    /// How far below the top of the screen the line holding `index` starts.
    func screenY(of index: Int) -> CGFloat? {
        guard let length = textStorage?.length, length > 0, let top = textLayoutManager?.top(of: max(0, min(index, length - 1))) else { return nil }
        return top + textContainerOrigin.y - visibleRect.minY
    }

    /// Scrolls so the line holding `index` starts `y` below the top of the screen.
    func place(_ index: Int, at y: CGFloat) {
        guard let scroll = enclosingScrollView, let length = textStorage?.length, length > 0,
              let top = textLayoutManager?.top(of: max(0, min(index, length - 1))) else { return }
        let target = max(0, top + textContainerOrigin.y - y)
        let clip = scroll.contentView
        if frame.height < target + clip.bounds.height { setFrameSize(NSSize(width: frame.width, height: target + clip.bounds.height)) }
        guard abs(clip.bounds.minY - target) > 0.5 else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: target))
        scroll.reflectScrolledClipView(clip)
    }

    /// What to hold still through a change at `range`: the change itself while it's on screen, else the top line, moved
    /// by what the change adds or takes above it.
    func hold(_ range: NSRange, delta: Int) -> (index: Int, y: CGFloat)? {
        if let y = screenY(of: range.location), y >= 0, y < visibleRect.height { return (range.location, y) }
        guard let first = firstVisible, let y = screenY(of: first) else { return nil }
        return (range.location < first ? max(0, first + delta) : first, y)
    }
}

final class SourceTextView: NoteTextView, NSTextViewDelegate {
    var onChange: () -> Void = {}
    var openGuide: @MainActor () -> Void = {}
    private var hint: HintLabel?
    var onScroll: @MainActor (Int, Double) -> Void = { _, _ in }
    var saveFile: (String, Data) -> String? = { _, _ in nil }
    private var styler: SourceStyler?
    private var lineStarts: [Int] = [0]
    private(set) var bubble: PreviewBubble?
    private var observer: NSObjectProtocol?
    private var held: (index: Int, y: CGFloat)?
    private static let promiseQueue = OperationQueue()
    let completion = CompletionMenu()
    private(set) var catalog = CompletionCatalog()
    private var assisting: (NoteAssist, MathSyntax)?
    private(set) var menuHost: NSHostingView<AnyView>?
    private var accent = CourseAccent.gray
    /// Where a link opened the note at, kept until the view is on screen and sized: placed before, the line lands
    /// wherever TextKit's first height estimate put it.
    private var revealing: Int?
    /// The line a link put on screen, held there until the user scrolls, clicks or types. Anything that lays the lines
    /// above out again (the scroller coming in narrows the column, the look changing restyles the text) moves them
    /// under a scroll left as it was, and the line slid off the screen.
    private var keeping: Int?
    /// The notes a block reference's card draws from, as the preview's do; without it references show no card.
    var cards: NoteEmbedSource?
    /// The workspace's `notesRevision`, so a card shows the other note as it is now.
    var cardsRevision = 0
    private(set) var card: ReferenceCardPage?
    /// The block reference the pointer rests on, and the wait before its card shows.
    private var hovered: NSRange?
    private var hovering: Task<Void, Never>?
    private var hoverArea: NSTrackingArea?

    func configure(accent: CourseAccent, syntax: MathSyntax, dark: Bool) {
        accentColors(accent)
        self.accent = accent
        let next = SourceStyler(accent: accent, syntax: syntax, baseURL: baseURL, dark: dark)
        let changed = styler.map { $0.accent != accent || $0.syntax != syntax || $0.dark != dark || $0.baseURL != baseURL } ?? true
        styler = next
        if changed { restyle() }
    }

    override func columnChanged() {
        updateBubble()
        updateHint()
    }

    /// Puts the caret at `location` and its line near the top of the screen, as the preview shows a heading or block.
    func reveal(_ location: Int) {
        revealing = location
        DispatchQueue.main.async { [weak self] in self?.runReveal() }
    }

    private func runReveal() {
        guard let at = revealing, let window, let clip = enclosingScrollView?.contentView, clip.bounds.height > 0 else { return }
        revealing = nil
        let i = min(at, (string as NSString).length)
        setSelectedRange(NSRange(location: i, length: 0))
        keeping = i
        placeKept()
        window.makeFirstResponder(self)
    }

    override func setFrameSize(_ size: NSSize) {
        let width = frame.width
        super.setFrameSize(size)
        if revealing != nil { DispatchQueue.main.async { [weak self] in self?.runReveal() } }
        if size.width != width { placeKeptSoon() }
    }

    private func placeKeptSoon() {
        guard keeping != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.placeKept() }
    }

    // The viewport is laid out again here: placing only scrolls, and the lines drawn stayed where the old layout had
    // them. Laying it out corrects TextKit's guess at the height of what's below, which can move the scroll in turn, so
    // the line is placed again until it stays.
    private func placeKept() {
        guard let keeping else { return }
        for _ in 0..<4 {
            place(keeping, at: NoteLook.margin)
            textLayoutManager?.textViewportLayoutController.layoutViewport()
            guard let y = screenY(of: keeping), abs(y - NoteLook.margin) > 0.5 else { return }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        keeping = nil
        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        keeping = nil
        hideCard()
        super.keyDown(with: event)
    }

    /// Everything shown comes from styling the text as it now stands, after every change, composing ones included; a
    /// change left unstyled even for a moment shows in plain text's 12-point font.
    func restyle() {
        guard let styler, let storage = textStorage else { return }
        styler.style(storage)
        lineStarts = SourceStyler.lines(storage.string).map(\.location)
        matchTyping()
        updateBubble()
        placeKeptSoon()
    }

    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: range, replacementString: replacementString) else { return false }
        if held == nil, let text = replacementString { held = hold(range, delta: text.utf16.count - range.length) }
        return true
    }

    override func didChangeText() {
        keeping = nil
        hideCard()
        restyle()
        if let held {
            self.held = nil
            place(held.index, at: held.y)
        }
        super.didChangeText()
        updateHint()
    }

    /// What's typed next looks like the text around it until it's styled; a plain-text view would use its own font.
    private func matchTyping() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let caret = min(selectedRange().location, storage.length)
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: caret, length: 0))
        let at = caret > paragraph.location ? caret - 1 : min(caret, storage.length - 1)
        let around = storage.attributes(at: at, effectiveRange: nil)
        var typing: [NSAttributedString.Key: Any] = [.foregroundColor: NoteLook.text]
        for key in [NSAttributedString.Key.font, .paragraphStyle, .noteCaret] { typing[key] = around[key] }
        typingAttributes = typing
    }

    /// A note opened: its text without an undo step.
    func load(_ text: String) {
        string = text
        undoManager?.removeAllActions(withTarget: self)
        restyle()
    }

    /// Text changed outside the editor (typed in the read view): only the changed span is swapped, so the editor keeps
    /// its scroll, caret and undo history.
    func replace(with text: String) {
        let old = Array(string.utf16), new = Array(text.utf16)
        var a = 0, b = 0
        while a < min(old.count, new.count), old[a] == new[a] { a += 1 }
        while b < min(old.count, new.count) - a, old[old.count - 1 - b] == new[new.count - 1 - b] { b += 1 }
        let range = NSRange(location: a, length: old.count - a - b)
        let insert = String(utf16CodeUnits: Array(new[a..<(new.count - b)]), count: new.count - a - b)
        let selection = selectedRange()
        guard shouldChangeText(in: range, replacementString: insert) else { return }
        textStorage?.replaceCharacters(in: range, with: insert)
        didChangeText()
        let shift = insert.utf16.count - range.length
        if selection.location >= NSMaxRange(range) { setSelectedRange(NSRange(location: selection.location + shift, length: selection.length)) }
    }

    func insertAtCaret(_ text: String) {
        apply(SourceEditing.Edit(range: selectedRange(), text: text, caret: selectedRange().location + text.utf16.count))
        window?.makeFirstResponder(self)
    }

    func insertMath(_ item: CompletionItem) {
        apply(MathSymbols.insertion(item, in: string as NSString, selection: selectedRange()))
        window?.makeFirstResponder(self)
    }

    func apply(_ edit: SourceEditing.Edit, reveal: Bool = true) {
        // Stepping over a closer changes no text, and an empty change would still be an undo step.
        if edit.range.length > 0 || !edit.text.isEmpty {
            guard shouldChangeText(in: edit.range, replacementString: edit.text) else { return }
            textStorage?.replaceCharacters(in: edit.range, with: edit.text)
            didChangeText()
        }
        setSelectedRange(edit.selection)
        if reveal { scrollRangeToVisible(selectedRange()) }
    }

    func textDidChange(_ notification: Notification) { onChange() }

    // A syllable ended without a keystroke (a click elsewhere, another app) changes no text, so nothing else hands it
    // to the binding.
    override func unmarkText() {
        super.unmarkText()
        onChange()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if !hasMarkedText() {
            matchTyping()
            refreshCompletion(opening: false)
        }
        updateBubble()
        updateHint()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        guard let clip = enclosingScrollView?.contentView else { return }
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let top = self.topLine(lineStarts: self.lineStarts)
                self.onScroll(top.line, top.frac)
                self.placeMenu()
                // The link moves away from the pointer resting on it.
                self.hideCard()
            }
        }
    }

    // MARK: Keys

    private var inCode: Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        return storage.attribute(.noteCode, at: min(selectedRange().location, storage.length - 1), effectiveRange: nil) != nil
    }

    override func insertNewline(_ sender: Any?) {
        if !hasMarkedText(), let edit = SourceEditing.newline(string as NSString, selectedRange(), inCode: inCode) { return apply(edit) }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        apply(SourceEditing.tab(string as NSString, selectedRange(), back: false, snippets: catalog.snippets, asciiMath: !catalog.tex))
    }

    override func insertBacktab(_ sender: Any?) {
        apply(SourceEditing.tab(string as NSString, selectedRange(), back: true, snippets: catalog.snippets, asciiMath: !catalog.tex))
    }

    // Nothing here acts while a syllable is being composed: the input method owns those keys, and a pair closed or a
    // menu item taken under it would split the syllable or eat the key that finishes it.

    override func insertText(_ text: Any, replacementRange: NSRange) {
        let typed = (text as? String) ?? (text as? NSAttributedString)?.string
        if !hasMarkedText(), let typed, replacementRange.location == NSNotFound || replacementRange == selectedRange(),
           let edit = SourceEditing.typed(typed, in: string as NSString, selection: selectedRange()) {
            apply(edit)
        } else {
            super.insertText(text, replacementRange: replacementRange)
        }
        refreshCompletion(opening: true)
    }

    override func deleteBackward(_ sender: Any?) {
        if !hasMarkedText(), let edit = SourceEditing.deleteBackward(in: string as NSString, selection: selectedRange()) {
            apply(edit)
        } else {
            super.deleteBackward(sender)
        }
        refreshCompletion(opening: false)
    }

    override func doCommand(by selector: Selector) {
        if completion.visible, !hasMarkedText() {
            switch selector {
            case #selector(moveUp(_:)): return completion.move(-1)
            case #selector(moveDown(_:)): return completion.move(1)
            case #selector(insertTab(_:)): return acceptCompletion()
            case #selector(insertNewline(_:)):
                if completion.query?.takesReturn == true { return acceptCompletion() }
                completion.hide()
                placeMenu()
            case #selector(cancelOperation(_:)):
                completion.hide()
                return placeMenu()
            default: break
            }
        }
        super.doCommand(by: selector)
    }

    // MARK: Completion

    func setAssist(_ assist: NoteAssist, syntax: MathSyntax) {
        if let assisting, assisting.0 == assist, assisting.1 == syntax { return }
        assisting = (assist, syntax)
        catalog = assist.catalog(syntax: syntax)
        if let links = assist.links {
            completion.more = { [weak self] query in
                guard let self else { return [] }
                return await links.candidates(for: query, text: self.string)
            }
        } else {
            completion.more = nil
        }
        completion.arrived = { [weak self] in self?.placeMenu() }
    }

    /// 편집 › 수식 기호 목록: types the `\` that lists every symbol and math snippet of the note's syntax, so the menu is
    /// the one typing it opens and Esc leaves the `\` as typing does. Only in a formula; elsewhere it beeps, as a menu
    /// command that can't act here does.
    @objc func showMathSymbols(_ sender: Any?) {
        let selection = selectedRange()
        guard !hasMarkedText(), selection.length == 0, SourcePlace.typing(at: selection.location, in: string as NSString).isMath else {
            return NSSound.beep()
        }
        insertText("\\", replacementRange: selection)
    }

    /// Opens, narrows or closes the menu for the text at the caret. Only typing opens it; a caret moved elsewhere
    /// keeps it only while it is still on the same kind of thing.
    func refreshCompletion(opening: Bool) {
        guard !hasMarkedText() else { return }
        let selection = selectedRange()
        if selection.length == 0, let query = Completion.query(in: string as NSString, caret: selection.location, catalog: catalog),
           opening || completion.query.map({ Self.sameKind($0.kind, query.kind) }) == true {
            let items = Completion.items(for: query, catalog: catalog)
            // A link's candidates all come late, from the app.
            if items.isEmpty, completion.more == nil || !CompletionMenu.late(query) { completion.hide() } else { completion.show(query, items) }
        } else {
            completion.hide()
        }
        // The menu and a card would both float by the line; the menu, being typed into, wins.
        if completion.visible { hideCard() }
        placeMenu()
    }

    /// A link's parts are one kind of thing to keep the menu on, whatever is typed in them.
    static func sameKind(_ a: CompletionQuery.Kind, _ b: CompletionQuery.Kind) -> Bool {
        if case .link = a, case .link = b { return true }
        return a == b
    }

    func acceptCompletion(_ index: Int? = nil) {
        if let index { completion.selected = index }
        guard var query = completion.query, var item = completion.current else { return }
        completion.hide()
        if item.id == InputGuide.menuItemID {
            apply(SourceEditing.Edit(range: query.range, text: "", caret: query.range.location))
            placeMenu()
            return openGuide()
        }
        if CompletionMenu.late(query), let links = assisting?.0.links {
            guard let taken = links.take(item, for: query, text: string) else { return placeMenu() }
            item = taken.item
            // The ID a block of this very note gets goes in first; the link moves along when it was after the block.
            if let own = taken.own {
                apply(own, reveal: false)
                if own.range.location <= query.range.location { query = query.shifted(by: own.text.utf16.count - own.range.length) }
            }
        }
        apply(Completion.edit(accepting: item, for: query, in: string as NSString))
        window?.makeFirstResponder(self)
        // A block left open (`> [!`, a fence) opens the menu for what comes next in it, as a file's link does at its
        // page; anything else would reopen the menu it just closed, as `\alpha` is still a command being typed.
        if query.kind == .slash || item.continues { refreshCompletion(opening: true) } else { placeMenu() }
    }

    /// Under the line being completed, or over it where the screen ends first, in the scroll view so the menu isn't
    /// clipped to the text column.
    func placeMenu() {
        guard completion.visible, let query = completion.query, let scroll = enclosingScrollView, let window else {
            menuHost?.isHidden = true
            return
        }
        let host = menuHost ?? {
            let host = NSHostingView(rootView: AnyView(EmptyView()))
            scroll.addSubview(host)
            menuHost = host
            return host
        }()
        if host.superview !== scroll { scroll.addSubview(host) }
        host.rootView = AnyView(CompletionMenuView(menu: completion) { [weak self] i in self?.acceptCompletion(i) }.courseAccent(accent))
        let size = CGSize(width: CompletionMenuView.width, height: CompletionMenuView.height(rows: completion.items.count))
        let screen = firstRect(forCharacterRange: NSRange(location: query.range.location, length: 0), actualRange: nil)
        let line = scroll.convert(window.convertFromScreen(screen), from: nil)
        let x = max(Theme.Space.s, min(line.minX - Theme.Space.m, scroll.bounds.maxX - size.width - Theme.Space.s))
        let gap = Theme.Space.xs
        let down = scroll.isFlipped ? line.maxY + gap : line.minY - gap - size.height
        let up = scroll.isFlipped ? line.minY - gap - size.height : line.maxY + gap
        let fits = scroll.isFlipped ? down + size.height <= scroll.bounds.maxY : down >= scroll.bounds.minY
        host.frame = NSRect(x: x, y: fits ? down : up, width: size.width, height: size.height)
        host.isHidden = false
    }

    /// 도움말 › 입력 안내 (⌘/), sent here while this note is being written, so the guide shows its math syntax.
    @objc func showInputGuide(_ sender: Any?) { openGuide() }

    // MARK: Tables

    /// A table key acts only with the caret in a table, where it is taken even when it can't be done (a move past the
    /// edge): falling through, ⌘ and an arrow would move the caret to the line's end instead.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, !hasMarkedText(), let shortcut = TableCommands.shortcut(of: event),
           let command = TableCommands.command(for: shortcut), let table = TableEditing.table(in: string as NSString, selection: selectedRange()) {
            if let edit = table.edit(command) { apply(edit) } else { NSSound.beep() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// With the caret in a table, its commands come first. A right-click outside the selection puts the caret there
    /// first, so the commands act on the cell clicked.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        if let i = characterIndex(at: convert(event.locationInWindow, from: nil)), !NSLocationInRange(i, selectedRange()) {
            setSelectedRange(NSRange(location: i, length: 0))
        }
        guard let menu, let table = TableEditing.table(in: string as NSString, selection: selectedRange()) else { return menu }
        menu.insertItem(TableCommands.menu(for: table) { [weak self] edit in
            self?.apply(edit)
            self?.window?.makeFirstResponder(self)
        }, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    // MARK: Clicks

    override func mouseDown(with event: NSEvent) {
        keeping = nil
        hideCard()
        let point = convert(event.locationInWindow, from: nil)
        if let i = characterIndex(at: point) {
            if openLink(at: i, event: event) { return }
            if event.modifierFlags.intersection([.command, .shift, .option]).isEmpty, event.clickCount == 1, toggleTask(at: i) { return }
        }
        super.mouseDown(with: event)
    }

    /// Ticks the task box at `i`, leaving the caret, and the screen, where they were.
    func toggleTask(at i: Int) -> Bool {
        var box = NSRange()
        guard let done = textStorage?.attribute(.noteTask, at: i, effectiveRange: &box) as? Bool, box.length == 3 else { return false }
        let selection = selectedRange()
        apply(SourceEditing.Edit(range: NSRange(location: box.location + 1, length: 1), text: done ? " " : "x", caret: selection.location), reveal: false)
        setSelectedRange(selection)
        return true
    }

    // MARK: Block reference card

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        hover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideCard()
    }

    // A syllable being composed is the input method's: a card over it would cover the candidates it lists.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        hideCard()
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        updateHint()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { hideCard() }
        super.viewWillMove(toWindow: newWindow)
    }

    /// The pointer resting on a block reference shows its card after a moment, as in the preview; moving onto other
    /// text takes it away. Never while a syllable is composed or the completion menu is open.
    func hover(at point: NSPoint) {
        let found = reference(at: point)
        if let found, found.range == hovered { return }
        hideCard()
        guard let found, cards != nil, !hasMarkedText(), !completion.visible else { return }
        hovered = found.range
        hovering = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.showCard(found.link, range: found.range)
        }
    }

    func hideCard() {
        hovering?.cancel()
        hovering = nil
        hovered = nil
        card?.hide()
    }

    /// The block reference under the point. `characterIndex` gives the nearest character, also past a line's end or
    /// beside the column, so the point must be on that character's own box.
    private func reference(at point: NSPoint) -> (link: WikiLink, range: NSRange)? {
        guard let window, let i = characterIndex(at: point), let found = wikiLink(at: i), found.link.blockID != nil else { return nil }
        let box = convert(window.convertFromScreen(firstRect(forCharacterRange: NSRange(location: i, length: 1), actualRange: nil)), from: nil)
        return box.insetBy(dx: -Theme.Space.xxs, dy: -Theme.Space.xxs).contains(point) ? found : nil
    }

    private func showCard(_ link: WikiLink, range: NSRange) {
        guard let cards, let styler, hovered == range, !hasMarkedText(), !completion.visible, let scroll = enclosingScrollView,
              let content = HTMLRenderer.referenceCard(link, embeds: cards.embeds(revision: cardsRevision, text: string)) else { return }
        let page = card ?? ReferenceCardPage()
        card = page
        if page.host.superview !== scroll { scroll.addSubview(page.host) }
        let width = min(columnWidth, scroll.bounds.width - 2 * Theme.Space.s)
        let tallest = (scroll.bounds.height / 2).rounded()
        page.load(content, math: styler.syntax.rawValue, accent: accent, baseURL: baseURL, width: width, maxHeight: tallest) { [weak self] height in
            guard let self, self.hovered == range, !self.hasMarkedText(), !self.completion.visible else { return }
            self.placeCard(page, range: range, size: CGSize(width: width, height: min(height, tallest)))
        }
    }

    /// Under the link, or over it where the screen ends first, in the scroll view so the card isn't clipped to the
    /// text column, as the completion menu is placed.
    private func placeCard(_ page: ReferenceCardPage, range: NSRange, size: CGSize) {
        guard let scroll = enclosingScrollView, let window else { return }
        let rect = { (i: Int) in scroll.convert(window.convertFromScreen(self.firstRect(forCharacterRange: NSRange(location: i, length: 1), actualRange: nil)), from: nil) }
        let first = rect(range.location), last = rect(NSMaxRange(range) - 1)
        let x = max(Theme.Space.s, min(first.minX - Theme.Space.m, scroll.bounds.maxX - size.width - Theme.Space.s))
        let gap = Theme.Space.xs
        let top = min(first.minY, last.minY), bottom = max(first.maxY, last.maxY)
        let down = scroll.isFlipped ? bottom + gap : top - gap - size.height
        let up = scroll.isFlipped ? top - gap - size.height : bottom + gap
        let fits = scroll.isFlipped ? down + size.height <= scroll.bounds.maxY : down >= scroll.bounds.minY
        page.host.resize(size)
        page.host.setFrameOrigin(NSPoint(x: x, y: fits ? down : up))
        page.host.isHidden = false
    }

    // MARK: Rendering bubble

    override func resignFirstResponder() -> Bool {
        defer {
            bubble?.removeFromSuperview()
            bubble = nil
            completion.hide()
            placeMenu()
            hint?.isHidden = true
        }
        return super.resignFirstResponder()
    }

    override func becomeFirstResponder() -> Bool {
        defer { DispatchQueue.main.async { [weak self] in self?.updateHint() } }
        // The math page may have left with another editor's window; the one being typed in shows the math now.
        NoteMath.shared.host(in: self)
        return super.becomeFirstResponder()
    }

    var hintShown: Bool { hint.map { !$0.isHidden } ?? false }

    /// "/ 블록 삽입" after the caret on an empty line (#395). A label over the text, not text: the input method, undo
    /// and the saved note never see it. A syllable being composed is in the text, so the line isn't empty and it goes.
    func updateHint() {
        let caret = selectedRange()
        guard window?.firstResponder === self, !hasMarkedText(), let window,
              SourceEditing.offersBlocks(in: string as NSString, selection: caret) else {
            hint?.isHidden = true
            return
        }
        let label = hint ?? {
            let label = HintLabel(labelWithAttributedString: NSAttributedString(string: String(localized: .notesGuideHint), attributes: [
                .font: NoteLook.font(NoteLook.body), .foregroundColor: NoteLook.text3,
            ]))
            label.setAccessibilityElement(false)
            label.sizeToFit()
            addSubview(label)
            hint = label
            return label
        }()
        let size = label.fittingSize
        var line = convert(window.convertFromScreen(firstRect(forCharacterRange: NSRange(location: caret.location, length: 0), actualRange: nil)), from: nil)
        // An empty note has no line laid out yet: its first line starts at the column's corner.
        if line.height < 1 {
            line = NSRect(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0), y: textContainerOrigin.y, width: 0, height: size.height)
        }
        // On the line's baseline side, where the caret is drawn (`NoteLines.caret`); just past the caret.
        label.frame = NSRect(x: line.minX + Theme.Space.xs, y: line.maxY - size.height, width: size.width, height: size.height)
        label.isHidden = false
    }

    /// With the caret in math or an image link, its rendering floats by the source, over the text, which keeps its place.
    func updateBubble() {
        let caret = selectedRange()
        var found: Rendering?
        if window?.firstResponder === self, caret.length == 0, let storage = textStorage, caret.location <= storage.length {
            found = rendering(at: caret.location, in: storage)
        }
        if let kept = bubble {
            // Under the pointer it stays while the caret goes elsewhere, or a long formula couldn't be scrolled to its
            // end; it goes when the pointer leaves (`PreviewBubble.onLeave`).
            if kept.hovered, found == nil || found?.image === kept.picture.image { return }
            // The same picture keeps its view, and where it's scrolled to follows the caret.
            if let found, found.image === kept.picture.image, found.size == kept.picture.frame.size, let origin = bubbleOrigin(kept.frame.size, found.span) {
                kept.setFrameOrigin(origin)
                kept.reveal(found.at)
                return
            }
        }
        bubble?.removeFromSuperview()
        bubble = nil
        guard let found else { return }
        // At its own size: a formula wider than the editor scrolls sideways in the bubble, as it does in the preview,
        // since shrunk to fit it was too small to read. A picture is already cut to a preview's size.
        let room = visibleRect.width - 2 * PreviewBubble.pad - 8
        let scale = found.math ? 1 : min(1, room / max(1, found.size.width))
        let view = PreviewBubble(image: found.image, size: CGSize(width: (found.size.width * scale).rounded(), height: (found.size.height * scale).rounded()),
                                 width: room + 2 * PreviewBubble.pad)
        guard let origin = bubbleOrigin(view.frame.size, found.span) else { return }
        view.setFrameOrigin(origin)
        view.onLeave = { [weak self] in self?.updateBubble() }
        addSubview(view)
        view.reveal(found.at)
        bubble = view
    }

    /// By the source at `span`: the formula starting where its source does, the padding reaching out to the left of it,
    /// under the source, or over it when the screen ends first; never pushing the text.
    private func bubbleOrigin(_ size: CGSize, _ span: NSRange) -> NSPoint? {
        guard let window, let storage = textStorage, NSMaxRange(span) <= storage.length, span.length > 0 else { return nil }
        let text = storage.string as NSString
        var end = NSMaxRange(span)
        while end > span.location + 1, text.character(at: end - 1) == 0x0A { end -= 1 }
        let line = { (i: Int) in self.convert(window.convertFromScreen(self.firstRect(forCharacterRange: NSRange(location: i, length: 1), actualRange: nil)), from: nil) }
        let first = line(span.location), last = line(end - 1)
        let x = max(0, min(first.minX - PreviewBubble.pad, bounds.maxX - size.width - 4))
        let under = last.maxY + 4, over = first.minY - 4 - size.height
        // In whole points: the scroller's clip view aligns itself to the screen's pixels, and off them it shifted the
        // picture by the fraction.
        return NSPoint(x: x.rounded(), y: (under + size.height <= visibleRect.maxY || over < visibleRect.minY ? under : over).rounded())
    }

    /// What the bubble shows: its picture, the source it's for, and how far into that source the caret is, which a
    /// formula wider than the bubble is scrolled to.
    private struct Rendering {
        let image: NSImage
        let size: CGSize
        let span: NSRange
        let math: Bool
        let at: CGFloat
    }

    /// The math is drawn after the caret came to it (`NoteMath`), and the caret may have moved on by then.
    private func redrawBubble() { updateBubble() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { NoteMath.shared.host(in: self, warm: true) }
    }

    /// What the caret is in: inline math or an image link it's past the start of, or any line of a math block.
    private func rendering(at caret: Int, in storage: NSTextStorage) -> Rendering? {
        guard let styler, storage.length > 0 else { return nil }
        let at = { (span: NSRange) in CGFloat(caret - span.location) / CGFloat(max(1, span.length)) }
        let all = NSRange(location: 0, length: storage.length)
        var span = NSRange()
        if caret > 0 {
            if let tex = storage.attribute(.noteMath, at: caret - 1, longestEffectiveRange: &span, in: all) as? String, caret > span.location,
               let picture = NoteMath.shared.picture(tex, syntax: styler.syntax, display: false, size: NoteLook.body, dark: styler.dark, trim: true,
                                                     ready: redrawBubble) {
                return Rendering(image: picture.image, size: picture.size, span: span, math: true, at: at(span))
            }
            if let source = storage.attribute(.noteImage, at: caret - 1, longestEffectiveRange: &span, in: all) as? String, caret > span.location,
               let image = NoteImages.load(source, base: baseURL) {
                // A preview, not the picture at its size: big enough to tell what it is, small enough to keep the note in view.
                let natural = image.size
                let scale = min(1, min(columnWidth, 480) / max(1, natural.width), 320 / max(1, natural.height))
                return Rendering(image: image, size: CGSize(width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded()),
                                 span: span, math: false, at: 0)
            }
        }
        if let tex = storage.attribute(.noteMathBlock, at: min(caret, storage.length - 1), longestEffectiveRange: &span, in: all) as? String,
           let picture = NoteMath.shared.picture(tex, syntax: styler.syntax, display: true, size: NoteLook.body, dark: styler.dark, trim: true,
                                                 ready: redrawBubble) {
            return Rendering(image: picture.image, size: picture.size, span: span, math: true, at: at(span))
        }
        return nil
    }

    // MARK: Files

    override func paste(_ sender: Any?) {
        if insertFiles(from: NSPasteboard.general, at: selectedRange().location) { return }
        let at = selectedRange()
        if let link = pastedNoteLink(NSPasteboard.general.string(forType: .string), into: string, at: at.location, name: linkName) {
            apply(SourceEditing.Edit(range: at, text: link, caret: at.location + link.utf16.count))
            return
        }
        pasteAsPlainText(sender)
    }

    private func hasFiles(_ info: NSDraggingInfo) -> Bool {
        let board = info.draggingPasteboard
        return board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || board.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
            || (board.string(forType: .string) == nil && board.canReadObject(forClasses: [NSImage.self], options: nil))
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        hasFiles(info) ? .copy : super.draggingEntered(info)
    }

    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        if hasFiles(info) {
            _ = super.draggingUpdated(info)
            return .copy
        }
        return super.draggingUpdated(info)
    }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        guard hasFiles(info) else { return super.performDragOperation(info) }
        let at = characterIndexForInsertion(at: convert(info.draggingLocation, from: nil))
        let board = info.draggingPasteboard
        if !board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]),
           let promises = board.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver], !promises.isEmpty {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            // folio:not-an-action a temporary folder for pasted files
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for promise in promises {
                promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: Self.promiseQueue) { [weak self] url, error in
                    guard error == nil, let data = try? Data(contentsOf: url) else { return }
                    let name = url.lastPathComponent
                    // folio:not-an-action a temporary folder for pasted files
                    try? FileManager.default.removeItem(at: url)
                    Task { @MainActor in
                        guard let self, let link = self.saveFile(name, data) else { return }
                        self.insertLinks([link], at: at)
                    }
                }
            }
            return true
        }
        return insertFiles(from: board, at: at)
    }

    /// Files go to `Notes/assets` and their links in here; read as text, a dropped image became its path.
    private func insertFiles(from board: NSPasteboard, at index: Int) -> Bool {
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let links = urls.compactMap { url in (try? Data(contentsOf: url)).flatMap { saveFile(url.lastPathComponent, $0) } }
            guard !links.isEmpty else { return false }
            insertLinks(links, at: index)
            return true
        }
        guard board.string(forType: .string) == nil, let image = (board.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first,
              let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
              let link = saveFile("Pasted \(Date.now.formatted(.iso8601.dateSeparator(.dash).timeSeparator(.omitted))).png", png) else { return false }
        insertLinks([link], at: index)
        return true
    }

    private func insertLinks(_ links: [String], at index: Int) {
        let at = min(index, (string as NSString).length)
        let text = links.joined(separator: "\n")
        let lead = at > 0 && (string as NSString).substring(with: NSRange(location: at - 1, length: 1)) != "\n" && text.hasPrefix("!") ? "\n" : ""
        apply(SourceEditing.Edit(range: NSRange(location: at, length: 0), text: lead + text, caret: at + lead.utf16.count + text.utf16.count))
        window?.makeFirstResponder(self)
    }
}

/// The empty line's hint, which a click goes through to the line under it.
final class HintLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Rendered math or an image over the text, by its source. A picture wider than the bubble scrolls sideways in
/// it, with a fade at an edge it runs on past.
final class PreviewBubble: NSView {
    /// The same on every side: a formula's picture is its ink (`NoteMath`), so this is all the room around it.
    static let pad = Theme.Space.m
    // Well past the padding, so it fades the formula itself and reads as more of it that way.
    static let fade = 2 * Theme.Space.xl

    let picture: NSImageView
    let scroller: BubbleScroller
    let leading = EdgeFade(leading: true), trailing = EdgeFade(leading: false)
    /// Whether the pointer is over it, which keeps it while the caret goes elsewhere (`SourceTextView.updateBubble`).
    var hovered = false
    var onLeave: (() -> Void)?
    let scrolls: Bool

    /// At most `width` wide; a wider picture scrolls in it.
    init(image: NSImage, size: CGSize, width: CGFloat) {
        let pad = Self.pad, border: CGFloat = 1
        let whole = CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad)
        let shown = CGSize(width: min(whole.width, max(width, 2 * pad)), height: whole.height)
        // Inside the border, so neither the picture scrolling by nor the fades over it cover it.
        let inner = NSRect(origin: .zero, size: shown).insetBy(dx: border, dy: border)
        picture = NSImageView(frame: NSRect(origin: CGPoint(x: pad - border, y: pad - border), size: size))
        scroller = BubbleScroller(frame: inner)
        scrolls = whole.width > shown.width
        super.init(frame: NSRect(origin: .zero, size: shown))
        wantsLayer = true
        layer?.cornerRadius = NoteLook.radius
        layer?.borderWidth = border
        shadow = NSShadow()
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        picture.image = image
        picture.imageScaling = .scaleAxesIndependently
        let document = NSView(frame: NSRect(x: 0, y: 0, width: whole.width - 2 * border, height: inner.height))
        document.addSubview(picture)
        scroller.documentView = document
        scroller.drawsBackground = false
        scroller.hasHorizontalScroller = false
        scroller.hasVerticalScroller = false
        scroller.verticalScrollElasticity = .none
        scroller.horizontalScrollElasticity = scrolls ? .automatic : .none
        scroller.wantsLayer = true
        scroller.layer?.cornerRadius = NoteLook.radius - border
        scroller.layer?.masksToBounds = true
        addSubview(scroller)
        scroller.tile()
        for (fade, x) in [(leading, inner.minX), (trailing, inner.maxX - Self.fade)] {
            fade.frame = NSRect(x: x, y: inner.minY, width: Self.fade, height: inner.height)
            fade.layer?.cornerRadius = NoteLook.radius - border
            addSubview(fade)
        }
        scroller.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroller.contentView)
        scrolled()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Scrolls to the part of the picture `fraction` of the way across it, the caret's place in the source,
    /// centered where the picture's ends allow.
    func reveal(_ fraction: CGFloat) {
        guard scrolls, let document = scroller.documentView else { return }
        let visible = scroller.bounds.width
        let x = min(max(0, fraction * document.frame.width - visible / 2), document.frame.width - visible)
        scroller.contentView.scroll(to: NSPoint(x: x.rounded(), y: 0))
        scroller.reflectScrolledClipView(scroller.contentView)
    }

    @objc private func scrolled() {
        let x = scroller.contentView.bounds.minX, end = (scroller.documentView?.frame.width ?? 0) - scroller.bounds.width
        leading.isHidden = !scrolls || x <= 0.5
        trailing.isHidden = !scrolls || x >= end - 0.5
    }

    // It covers the lines under the source it shows; a click there is meant for them, and taken here it went nowhere.
    // Over a picture that scrolls, the scroller takes the wheel, and passes a click on (`BubbleScroller`).
    override func hitTest(_ point: NSPoint) -> NSView? {
        scrolls && frame.contains(point) ? scroller : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    // Shown under a pointer that hasn't moved, it gets no `mouseEntered`.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { hovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { left() }

    func left() {
        hovered = false
        onLeave?()
    }

    override var wantsUpdateLayer: Bool { true }

    // A layer holds fixed CGColors. Resolved here, under the view's own appearance, they follow a theme change;
    // resolved at init they took whatever appearance was current then, so a light window got a dark bubble.
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NoteLook.card.cgColor
            layer?.borderColor = NoteLook.lineSoft.cgColor
        }
    }
}

/// The bubble's sideways scroll. A wheel or swipe that's mostly up or down is the note's, not lost on a bubble that
/// can't go that way; a click goes on up to the text under it.
final class BubbleScroller: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) { nextResponder?.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
}

/// The card's color fading out over a scrolling picture's edge.
final class EdgeFade: NSView {
    private let leading: Bool

    init(leading: Bool) {
        self.leading = leading
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.maskedCorners = leading ? [.layerMinXMinYCorner, .layerMinXMaxYCorner] : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }

    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer { CAGradientLayer() }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        guard let gradient = layer as? CAGradientLayer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            gradient.colors = [NoteLook.card.cgColor, NoteLook.card.withAlphaComponent(0).cgColor]
        }
        gradient.startPoint = CGPoint(x: leading ? 0 : 1, y: 0.5)
        gradient.endPoint = CGPoint(x: leading ? 1 : 0, y: 0.5)
    }
}
#else
extension MarkdownEditor: UIViewRepresentable {
    func makeUIView(context: Context) -> SourceTextView {
        let view = SourceTextView()
        view.onChange = { [weak coordinator = context.coordinator] in coordinator?.changed() }
        context.coordinator.view = view
        view.load(text)
        update(view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
               openLink: context.environment.openLink)
        return view
    }

    func updateUIView(_ view: SourceTextView, context: Context) {
        update(view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
               openLink: context.environment.openLink)
    }
}

/// The iPad's text view for notes: TextKit 2, the column centered at the note measure.
class NoteTextView: UITextView {
    private let content = NSTextContentStorage()
    var baseURL: URL?
    var openNote: (String) -> Void = { _ in }
    var linkOpener = OpenLinkAction()
    /// Names what a pasted `folio://` address points at (`NoteEmbedSource.name`).
    var linkName: (AppLink) -> String? = { _ in nil }
    private var column: CGFloat = 0

    init() {
        let manager = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        manager.textContainer = container
        content.addTextLayoutManager(manager)
        super.init(frame: .zero, textContainer: container)
        backgroundColor = .clear
        alwaysBounceVertical = true
        // The room past the note's end is a content inset, and UIKit would shorten the indicator by it too.
        automaticallyAdjustsScrollIndicatorInsets = false
        verticalScrollIndicatorInsets = .zero
        autocorrectionType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        spellCheckingType = .no
        textContainerInset = UIEdgeInsets(top: NoteLook.margin, left: NoteLook.margin, bottom: NoteLook.margin, right: NoteLook.margin)
    }

    required init?(coder: NSCoder) { fatalError() }

    var string: String {
        get { text }
        set { text = newValue }
    }

    func hasMarkedText() -> Bool { markedTextRange != nil }

    var columnWidth: CGFloat { max(120, min(NoteLook.measure, bounds.width) - 2 * NoteLook.margin) }

    func accentColors(_ accent: CourseAccent) {
        tintColor = accent.native
    }

    override func layoutSubviews() {
        let inset = max(NoteLook.margin, (bounds.width - NoteLook.measure) / 2 + NoteLook.margin)
        if textContainerInset.left != inset { textContainerInset = UIEdgeInsets(top: NoteLook.margin, left: inset, bottom: NoteLook.margin, right: inset) }
        let bottom = NoteOverscroll.bottom(bounds.height)
        if contentInset.bottom != bottom { contentInset.bottom = bottom }
        super.layoutSubviews()
        if columnWidth != column {
            column = columnWidth
            columnChanged()
        }
    }

    func columnChanged() {}

    override func caretRect(for position: UITextPosition) -> CGRect {
        NoteLines.caret(super.caretRect(for: position), at: offset(from: beginningOfDocument, to: position), in: textStorage)
    }

    func characterIndex(at point: CGPoint) -> Int? {
        guard let position = closestPosition(to: point) else { return nil }
        let i = offset(from: beginningOfDocument, to: position)
        return i < textStorage.length ? i : nil
    }

    func topLine(lineStarts: [Int]) -> (line: Int, frac: Double) {
        guard let manager = textLayoutManager else { return (1, 0) }
        let y = max(0, contentOffset.y - textContainerInset.top)
        guard let fragment = manager.textLayoutFragment(for: CGPoint(x: 0, y: y)) else { return (1, 0) }
        let offset = manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location)
        let line = (lineStarts.lastIndex { $0 <= offset } ?? 0) + 1
        let frame = fragment.layoutFragmentFrame
        return (line, frame.height > 0 ? min(1, max(0, (y - frame.minY) / frame.height)) : 0)
    }
}

/// shortcut: on the iPad, pasted or dropped pictures, ⌘-click links, ticking a task by its box and the bubble that shows
/// math and images rendered are Mac-only for now; add them when the iPad is used for writing.
final class SourceTextView: NoteTextView, UITextViewDelegate {
    var onChange: () -> Void = {}
    var openGuide: @MainActor () -> Void = {}
    var onScroll: @MainActor (Int, Double) -> Void = { _, _ in }
    var saveFile: (String, Data) -> String? = { _, _ in nil }
    private var styler: SourceStyler?
    private var lineStarts: [Int] = [0]
    private var snippets: [Snippet] = []
    private var revealing: Int?
    private var asciiMath = false

    override init() {
        super.init()
        delegate = self
    }

    // Nothing shows math on the iPad yet (the bubble and the completion menu are the Mac's), but when it does it draws
    // it the Mac's way, in this view's window.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { NoteMath.shared.host(in: self) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(accent: CourseAccent, syntax: MathSyntax, dark: Bool) {
        accentColors(accent)
        let next = SourceStyler(accent: accent, syntax: syntax, baseURL: baseURL, dark: dark)
        let changed = styler.map { $0.accent != accent || $0.syntax != syntax || $0.dark != dark || $0.baseURL != baseURL } ?? true
        styler = next
        if changed { restyle() }
    }

    /// Scrolls the line holding `location` near the top and puts the selection there, without taking focus: on the
    /// iPad that would bring up the keyboard over the note just opened.
    func reveal(_ location: Int) {
        revealing = location
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let at = revealing, window != nil, bounds.height > 0 else { return }
        revealing = nil
        let i = min(at, textStorage.length)
        selectedRange = NSRange(location: i, length: 0)
        guard textStorage.length > 0, let top = textLayoutManager?.top(of: min(i, textStorage.length - 1)) else { return }
        let bottom = max(0, contentSize.height + contentInset.bottom - bounds.height)
        setContentOffset(CGPoint(x: 0, y: min(bottom, max(0, top + textContainerInset.top - NoteLook.margin))), animated: false)
    }

    /// The completion menu, and so link completion, is Mac-only for now (#31); pairs, lists and snippets on Tab work
    /// here too.
    func setAssist(_ assist: NoteAssist, syntax: MathSyntax) {
        snippets = assist.snippets(syntax: syntax)
        asciiMath = syntax == .asciimath
    }

    func restyle() {
        guard let styler else { return }
        styler.style(textStorage)
        lineStarts = SourceStyler.lines(textStorage.string).map(\.location)
    }

    func load(_ text: String) {
        self.text = text
        restyle()
    }

    func replace(with text: String) {
        let old = Array(string.utf16), new = Array(text.utf16)
        var a = 0, b = 0
        while a < min(old.count, new.count), old[a] == new[a] { a += 1 }
        while b < min(old.count, new.count) - a, old[old.count - 1 - b] == new[new.count - 1 - b] { b += 1 }
        let range = NSRange(location: a, length: old.count - a - b)
        let insert = String(utf16CodeUnits: Array(new[a..<(new.count - b)]), count: new.count - a - b)
        let selection = selectedRange
        textStorage.replaceCharacters(in: range, with: insert)
        restyle()
        let shift = insert.utf16.count - range.length
        if selection.location >= NSMaxRange(range) { selectedRange = NSRange(location: selection.location + shift, length: selection.length) }
    }

    func insertAtCaret(_ text: String) {
        apply(SourceEditing.Edit(range: selectedRange, text: text, caret: selectedRange.location + text.utf16.count))
        becomeFirstResponder()
    }

    /// Without taking focus, unlike `insertAtCaret`: the keyboard would come up over the palette still open for the
    /// next symbol.
    func insertMath(_ item: CompletionItem) {
        apply(MathSymbols.insertion(item, in: string as NSString, selection: selectedRange))
    }

    override func paste(_ sender: Any?) {
        let at = selectedRange
        if let link = pastedNoteLink(UIPasteboard.general.string, into: string, at: at.location, name: linkName) {
            apply(SourceEditing.Edit(range: at, text: link, caret: at.location + link.utf16.count))
            return
        }
        super.paste(sender)
    }

    func apply(_ edit: SourceEditing.Edit) {
        textStorage.replaceCharacters(in: edit.range, with: edit.text)
        selectedRange = edit.selection
        restyle()
        onChange()
        scrollRangeToVisible(selectedRange)
    }

    private var inCode: Bool {
        guard textStorage.length > 0 else { return false }
        return textStorage.attribute(.noteCode, at: min(selectedRange.location, textStorage.length - 1), effectiveRange: nil) != nil
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard markedTextRange == nil else { return true }
        if text == "\n", let edit = SourceEditing.newline(textStorage.string as NSString, range, inCode: inCode) {
            apply(edit)
            return false
        }
        let source = textStorage.string as NSString
        if text == "\t" {
            apply(SourceEditing.tab(source, range, back: false, snippets: snippets, asciiMath: asciiMath))
            return false
        }
        if text.isEmpty, range.length == 1, selectedRange.length == 0,
           let edit = SourceEditing.deleteBackward(in: source, selection: NSRange(location: NSMaxRange(range), length: 0)) {
            apply(edit)
            return false
        }
        if let edit = SourceEditing.typed(text, in: source, selection: range) {
            apply(edit)
            return false
        }
        return true
    }

    // UIKit drops the composition if the marked text's attributes change under it.
    func textViewDidChange(_ textView: UITextView) {
        if markedTextRange == nil { restyle() }
        onChange()
    }

    // A syllable ended without a keystroke (a tap elsewhere, the app leaving) changes no text, so no
    // `textViewDidChange` styles it or hands it to the binding.
    override func unmarkText() {
        super.unmarkText()
        restyle()
        onChange()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let top = topLine(lineStarts: lineStarts)
        onScroll(top.line, top.frac)
    }

    // MARK: Tables

    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + TableCommands.keyCommands(action: #selector(runTableCommand(_:)))
    }

    /// 도움말 › 입력 안내 (⌘/ on a keyboard), sent here while this note is being written, so the guide shows its math
    /// syntax. The note bar's button is the way by touch. No empty-line hint here: it points at the `/` menu, which the
    /// iPad doesn't have yet (#31).
    @objc func showInputGuide(_ sender: Any?) { openGuide() }

    /// A table key outside a table, or one that can't be done there, is left to the text view.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard action == #selector(runTableCommand(_:)) else { return super.canPerformAction(action, withSender: sender) }
        return markedTextRange == nil && tableEdit(sender) != nil
    }

    private func tableEdit(_ sender: Any?) -> SourceEditing.Edit? {
        guard let raw = (sender as? UIKeyCommand)?.propertyList as? String, let command = TableCommand(rawValue: raw) else { return nil }
        return TableEditing.edit(command, in: textStorage.string as NSString, selection: selectedRange)
    }

    @objc func runTableCommand(_ sender: UIKeyCommand) {
        if let edit = tableEdit(sender) { apply(edit) }
    }
}
#endif

extension NSTextLayoutManager {
    /// The top of the line holding character `index`, laid out as far as there.
    func top(of index: Int) -> CGFloat? {
        guard let location = location(documentRange.location, offsetBy: index) else { return nil }
        ensureLayout(for: NSTextRange(location: documentRange.location, end: location) ?? documentRange)
        return textLayoutFragment(for: location)?.layoutFragmentFrame.minY
    }
}
