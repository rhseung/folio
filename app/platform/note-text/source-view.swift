import FolioDomain
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

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: MarkdownEditor
        weak var view: SourceTextView?
        /// Set while SwiftUI updates the view: an edit made then is the binding's own text coming in.
        var updating = false

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func changed() {
            guard let view, !view.hasMarkedText() else { return }
            if !updating, parent.text != view.string { parent.text = view.string }
        }
    }

    @MainActor func update(_ view: SourceTextView, _ coordinator: Coordinator, accent: CourseAccent, dark: Bool) {
        coordinator.parent = self
        coordinator.updating = true
        defer { coordinator.updating = false }
        view.baseURL = baseURL
        view.saveFile = saveFile
        view.openNote = openNote
        view.onScroll = onScroll
        view.configure(accent: accent, syntax: math, dark: dark)
        if view.string != text { view.replace(with: text) }
        if let insert {
            view.insertAtCaret(insert)
            DispatchQueue.main.async { self.insert = nil }
        }
    }
}

/// Where a click on a note's link goes, from either view.
@MainActor enum NoteLinks {
    static func open(_ href: String, base: URL?, openNote: (String) -> Void) {
        guard let url = URL(string: href, relativeTo: base) ?? URL(string: href.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "") else { return }
        switch url.scheme {
        case "folio" where url.host == "note":
            openNote(String(url.path.dropFirst()))
        case "file" where url.pathExtension == "md":
            openNote(url.deletingPathExtension().lastPathComponent)
        case "http", "https", "obsidian", "mailto":
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
        default:
            break
        }
    }
}

/// Room past the note's end. The editor's last line comes up to the middle of the screen, since one writes at the end;
/// the preview's to the top, since its blocks stand further apart than the source's lines and it must still reach the
/// line the editor shows at the top.
enum NoteOverscroll {
    static func bottom(_ height: CGFloat, preview: Bool) -> CGFloat {
        preview ? max(0, height - 2 * NoteLook.margin) : (height / 2).rounded()
    }
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
        update(view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? SourceTextView else { return }
        update(view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark)
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
        findBarPosition = .aboveContent
        document.minSize = .zero
        document.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        document.isVerticallyResizable = true
        document.isHorizontallyResizable = false
        document.autoresizingMask = [.width]
        documentView = document
        contentView.postsBoundsChangedNotifications = true
        automaticallyAdjustsContentInsets = false
    }

    required init?(coder: NSCoder) { fatalError() }

    // The room past the note's end is a content inset, and AppKit insets the scrollers by it too: the track stopped
    // at half the editor's height and near the top of the preview. A negative `scrollerInsets` doesn't undo that, so
    // the vertical scroller is stretched back to the bottom after AppKit places it.
    override func tile() {
        let bottom = NoteOverscroll.bottom(frame.height, preview: documentView is ReaderTextView)
        if contentInsets.bottom != bottom { contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0) }
        super.tile()
        if let scroller = verticalScroller, scroller.frame.maxY < bounds.maxY {
            scroller.frame.size.height = bounds.maxY - scroller.frame.minY
        }
    }
}

/// A TextKit 2 text view for notes: the column centered at the note measure, `NoteFragment`s drawn, and the note's own
/// clicks (⌘ on a link, a task's box) taken before the text view's.
class NoteTextView: NSTextView {
    let layout = NoteLayout()
    private let content = NSTextContentStorage()
    var baseURL: URL?
    var openNote: (String) -> Void = { _ in }
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
        manager.delegate = layout
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

    /// The text column's width, which pictures fit.
    var columnWidth: CGFloat { max(120, min(NoteLook.measure, bounds.width) - 2 * NoteLook.margin) }

    func accentColors(_ accent: CourseAccent) {
        layout.accent = accent.native
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
        if let wiki = attributes[.noteWiki] as? String {
            openNote(wiki)
            return true
        }
        if let href = attributes[.noteHref] as? String {
            NoteLinks.open(href, base: baseURL, openNote: openNote)
            return true
        }
        return false
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
    var onScroll: @MainActor (Int, Double) -> Void = { _, _ in }
    var saveFile: (String, Data) -> String? = { _, _ in nil }
    private var styler: SourceStyler?
    private var lineStarts: [Int] = [0]
    private var bubble: NSView?
    private var observer: NSObjectProtocol?
    private var held: (index: Int, y: CGFloat)?
    private static let promiseQueue = OperationQueue()

    func configure(accent: CourseAccent, syntax: MathSyntax, dark: Bool) {
        accentColors(accent)
        let next = SourceStyler(accent: accent, syntax: syntax, baseURL: baseURL, dark: dark)
        let changed = styler.map { $0.accent != accent || $0.syntax != syntax || $0.dark != dark || $0.baseURL != baseURL } ?? true
        styler = next
        if changed { restyle() }
    }

    override func columnChanged() { updateBubble() }

    /// Everything shown comes from styling the text as it now stands, after every change, composing ones included; a
    /// change left unstyled even for a moment shows in plain text's 12-point font.
    func restyle() {
        guard let styler, let storage = textStorage else { return }
        styler.style(storage)
        lineStarts = SourceStyler.lines(storage.string).map(\.location)
        matchTyping()
        updateBubble()
    }

    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: range, replacementString: replacementString) else { return false }
        if held == nil, let text = replacementString { held = hold(range, delta: text.utf16.count - range.length) }
        return true
    }

    override func didChangeText() {
        restyle()
        if let held {
            self.held = nil
            place(held.index, at: held.y)
        }
        super.didChangeText()
    }

    /// What's typed next looks like the text around it until it's styled; a plain-text view would use its own font.
    private func matchTyping() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let caret = min(selectedRange().location, storage.length)
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: caret, length: 0))
        let at = caret > paragraph.location ? caret - 1 : min(caret, storage.length - 1)
        let around = storage.attributes(at: at, effectiveRange: nil)
        var typing: [NSAttributedString.Key: Any] = [.foregroundColor: NoteLook.text]
        for key in [NSAttributedString.Key.font, .paragraphStyle, .noteRaise, .noteCaret] { typing[key] = around[key] }
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

    func apply(_ edit: SourceEditing.Edit, reveal: Bool = true) {
        guard shouldChangeText(in: edit.range, replacementString: edit.text) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.text)
        didChangeText()
        setSelectedRange(NSRange(location: edit.caret, length: 0))
        if reveal { scrollRangeToVisible(selectedRange()) }
    }

    func textDidChange(_ notification: Notification) { onChange() }

    func textViewDidChangeSelection(_ notification: Notification) {
        if !hasMarkedText() { matchTyping() }
        updateBubble()
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

    override func insertTab(_ sender: Any?) { apply(SourceEditing.indent(string as NSString, selectedRange(), out: false)) }
    override func insertBacktab(_ sender: Any?) { apply(SourceEditing.indent(string as NSString, selectedRange(), out: true)) }

    // MARK: Clicks

    override func mouseDown(with event: NSEvent) {
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

    // MARK: Rendering bubble

    override func resignFirstResponder() -> Bool {
        defer { bubble?.removeFromSuperview(); bubble = nil }
        return super.resignFirstResponder()
    }

    /// With the caret in math or an image link, its rendering floats by the source, over the text, which keeps its place.
    func updateBubble() {
        bubble?.removeFromSuperview()
        bubble = nil
        let caret = selectedRange()
        guard window?.firstResponder === self, caret.length == 0, let storage = textStorage, caret.location <= storage.length,
              let shown = rendering(at: caret.location, in: storage), let window else { return }
        let text = storage.string as NSString
        var end = NSMaxRange(shown.span)
        while end > shown.span.location + 1, text.character(at: end - 1) == 0x0A { end -= 1 }
        let line = { (i: Int) in self.convert(window.convertFromScreen(self.firstRect(forCharacterRange: NSRange(location: i, length: 1), actualRange: nil)), from: nil) }
        let first = line(shown.span.location), last = line(end - 1)
        let view = PreviewBubble(image: shown.image, size: shown.size)
        let size = view.frame.size
        let x = max(0, min(first.minX - 10, bounds.maxX - size.width - 4))
        // Under the source, or over it when the screen ends first; never pushing the text.
        let under = last.maxY + 4, over = first.minY - 4 - size.height
        let y = under + size.height <= visibleRect.maxY || over < visibleRect.minY ? under : over
        view.setFrameOrigin(NSPoint(x: x, y: y))
        addSubview(view)
        bubble = view
    }

    /// What the caret is in: inline math or an image link it's past the start of, or any line of a math block.
    private func rendering(at caret: Int, in storage: NSTextStorage) -> (image: NSImage, size: CGSize, span: NSRange)? {
        guard let styler, storage.length > 0 else { return nil }
        let all = NSRange(location: 0, length: storage.length)
        var span = NSRange()
        if caret > 0 {
            if let tex = storage.attribute(.noteMath, at: caret - 1, longestEffectiveRange: &span, in: all) as? String, caret > span.location,
               let picture = NoteMath.picture(tex, syntax: styler.syntax, display: false, size: NoteLook.body * 1.05, color: NoteLook.text, dark: styler.dark) {
                return (picture.image, picture.size, span)
            }
            if let source = storage.attribute(.noteImage, at: caret - 1, longestEffectiveRange: &span, in: all) as? String, caret > span.location,
               let image = NoteImages.load(source, base: baseURL) {
                // A preview, not the picture at its size: big enough to tell what it is, small enough to keep the note in view.
                let natural = image.size
                let scale = min(1, min(columnWidth, 480) / max(1, natural.width), 320 / max(1, natural.height))
                return (image, CGSize(width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded()), span)
            }
        }
        let at = min(caret, storage.length - 1)
        if let tex = storage.attribute(.noteMathBlock, at: at, longestEffectiveRange: &span, in: all) as? String,
           let picture = NoteMath.picture(tex, syntax: styler.syntax, display: true, size: NoteLook.body * 1.1, color: NoteLook.text, dark: styler.dark) {
            return (picture.image, picture.size, span)
        }
        return nil
    }

    // MARK: Files

    override func paste(_ sender: Any?) {
        if insertFiles(from: NSPasteboard.general, at: selectedRange().location) { return }
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

/// Rendered math or an image over the text, by its source.
final class PreviewBubble: NSView {
    init(image picture: NSImage, size: CGSize) {
        let pad = CGSize(width: 10, height: 6)
        super.init(frame: NSRect(origin: .zero, size: CGSize(width: size.width + 2 * pad.width, height: size.height + 2 * pad.height)))
        wantsLayer = true
        layer?.cornerRadius = NoteLook.radius
        layer?.borderWidth = 1
        shadow = NSShadow()
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        let image = NSImageView(frame: NSRect(origin: CGPoint(x: pad.width, y: pad.height), size: size))
        image.image = picture
        image.imageScaling = .scaleAxesIndependently
        addSubview(image)
    }

    required init?(coder: NSCoder) { fatalError() }

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
#else
extension MarkdownEditor: UIViewRepresentable {
    func makeUIView(context: Context) -> SourceTextView {
        let view = SourceTextView()
        view.onChange = { [weak coordinator = context.coordinator] in coordinator?.changed() }
        context.coordinator.view = view
        view.load(text)
        update(view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark)
        return view
    }

    func updateUIView(_ view: SourceTextView, context: Context) {
        update(view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark)
    }
}

/// The iPad's text view for notes: TextKit 2, the column centered at the note measure, `NoteFragment`s drawn.
class NoteTextView: UITextView {
    let layout = NoteLayout()
    private let content = NSTextContentStorage()
    var baseURL: URL?
    var openNote: (String) -> Void = { _ in }
    private var column: CGFloat = 0

    init() {
        let manager = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        manager.textContainer = container
        content.addTextLayoutManager(manager)
        super.init(frame: .zero, textContainer: container)
        manager.delegate = layout
        backgroundColor = .clear
        alwaysBounceVertical = true
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
        layout.accent = accent.native
        tintColor = accent.native
    }

    override func layoutSubviews() {
        let inset = max(NoteLook.margin, (bounds.width - NoteLook.measure) / 2 + NoteLook.margin)
        if textContainerInset.left != inset { textContainerInset = UIEdgeInsets(top: NoteLook.margin, left: inset, bottom: NoteLook.margin, right: inset) }
        let bottom = NoteOverscroll.bottom(bounds.height, preview: self is ReaderTextView)
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
    var onScroll: @MainActor (Int, Double) -> Void = { _, _ in }
    var saveFile: (String, Data) -> String? = { _, _ in nil }
    private var styler: SourceStyler?
    private var lineStarts: [Int] = [0]

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(accent: CourseAccent, syntax: MathSyntax, dark: Bool) {
        accentColors(accent)
        let next = SourceStyler(accent: accent, syntax: syntax, baseURL: baseURL, dark: dark)
        let changed = styler.map { $0.accent != accent || $0.syntax != syntax || $0.dark != dark || $0.baseURL != baseURL } ?? true
        styler = next
        if changed { restyle() }
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

    func apply(_ edit: SourceEditing.Edit) {
        textStorage.replaceCharacters(in: edit.range, with: edit.text)
        selectedRange = NSRange(location: edit.caret, length: 0)
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
        if text == "\t" {
            apply(SourceEditing.indent(textStorage.string as NSString, range, out: false))
            return false
        }
        return true
    }

    // UIKit drops the composition if the marked text's attributes change under it.
    func textViewDidChange(_ textView: UITextView) {
        if markedTextRange == nil { restyle() }
        onChange()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let top = topLine(lineStarts: lineStarts)
        onScroll(top.line, top.frac)
    }
}
#endif
