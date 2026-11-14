import FolioDomain
import FolioMarkdown
import SwiftUI

struct MarkdownEditor {
    @Binding var text: String
    var baseURL: URL?
    var math: MathSyntax
    @Binding var insert: String?
    var saveFile: (String, Data) -> String?
    var openNote: (String) -> Void
    var onScroll: @MainActor (Int, Double) -> Void = { _, _ in }
    var assist = NoteAssist()
    var anchor: AppLink.Anchor?
    var embeds: NoteEmbedSource?
    var revision = 0
    var insertMath: Binding<CompletionItem?> = .constant(nil)
    var openGuide: @MainActor () -> Void = {}
    var views: NoteViews?

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: MarkdownEditor
        weak var view: SourceTextView?
        var updating = false
        var revealed: AppLink.Anchor?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func changed() {
            guard let view, !view.hasMarkedText() else { return }
            if !updating, parent.text != view.string { parent.text = view.string }
        }
    }

    @MainActor func update(
        _ view: SourceTextView, _ coordinator: Coordinator, accent: CourseAccent, dark: Bool, openLink: OpenLinkAction = OpenLinkAction()
    ) {
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
        view.cards = embeds
        view.cardsRevision = revision
        #endif

        // 바인딩에는 아직 조합 중인 음절이 없다. 이때 텍스트를 바꾸면 입력기가 조합하던 음절이 지워지고, 입력기는 그다음 자모부터 빈칸을 사이에 두고 입력한다.
        if view.string != text, !view.hasMarkedText() { view.replace(with: text) }
        // 노트 텍스트가 들어오기 전에는 앵커를 찾지 않는다. 모델은 뷰를 만든 뒤에 텍스트를 읽으므로, 빈 텍스트에서 찾으면 앵커를 찾지 못하고 포기한다. 미리보기처럼 앵커가 없으면 기록을 지운다. 그래야
        // 앵커 없이 노트로 돌아왔다가 다시 앵커로 앞으로 갈 때 캐럿이 다시 움직인다.
        if anchor == nil { coordinator.revealed = nil }
        if let anchor, anchor != coordinator.revealed, !text.isEmpty, view.string == text {
            coordinator.revealed = anchor
            if let location = anchor.location(in: text) { view.reveal(location) }
        }

        afterUpdate($insert) { view.insertAtCaret($0) }
        afterUpdate(insertMath) { view.insertMath($0) }
    }

    // 바인딩 값은 갱신이 끝난 뒤에 넣는다. 갱신 중에 한 편집은 `text`에 닿지 않고(`updating`), 바인딩을 비우면서 생기는 갱신이 텍스트를 되돌리기 때문이다. 넣을 때 값을 다시 확인하므로,
    // 넣기 전에 갱신이 두 번 돌아도 한 번만 넣는다.
    @MainActor private func afterUpdate<Value>(_ binding: Binding<Value?>, _ put: @escaping @MainActor (Value) -> Void) {
        guard binding.wrappedValue != nil else { return }
        DispatchQueue.main.async {
            guard let value = binding.wrappedValue else { return }
            binding.wrappedValue = nil
            put(value)
        }
    }
}

enum NoteOverscroll {
    static func bottom(_ height: CGFloat) -> CGFloat { (height / 2).rounded() }
}

func pastedNoteLink(_ pasted: String?, into text: String, at caret: Int, name: (AppLink) -> String?) -> String? {
    guard let pasted = pasted?.trimmingCharacters(in: .whitespacesAndNewlines), let link = AppLink(string: pasted),
        WikiLink.pastesAsLink(in: text as NSString, at: caret)
    else { return nil }
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
        update(
            view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
            openLink: context.environment.openLink)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? SourceTextView else { return }
        update(
            view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
            openLink: context.environment.openLink)
    }
}

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
        documentCursor = .iBeam
    }

    required init?(coder: NSCoder) { fatalError() }

    #if DEBUG
    private(set) var wheels = 0

    override func scrollWheel(with event: NSEvent) {
        wheels += 1
        super.scrollWheel(with: event)
    }
    #endif

    // 노트 위의 모든 클릭은 AppKit의 hit test 결과와 상관없이 여기로 보낸다. 기본 clip view에서는 scroll view가 문서 위의 클릭을 직접 가져갔고, `NoteClipView`에서는
    // 가장 깊은 뷰를 돌려준다. 노트가 텍스트 위에 올린 뷰(미리보기 말풍선)는 클릭을 받지 않는다. 노트 끝 아래의 여백은 노트의 어느 부분에도 속하지 않는 clip view의 영역이라 클릭이 아무 데도 가지
    // 않았으므로, 노트가 받아 캐럿을 끝에 둔다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard let hit, let document = documentView, hit === self || hit === contentView || hit.isDescendant(of: document) else {
            return hit
        }
        return document
    }
}

// 노트 끝 아래의 여백을 스크롤할 문서로 더한다. bottom content inset으로 두면 clip view가 scroll view에 남기는 띠가 되어, 텍스트 위의 클릭도 scroll view의 배경으로
// 갔다. 또 방금 연 노트가 그 띠 위까지만 그려져서, 스크롤하기 전까지 화면 아래 절반이 비고 클릭도 받지 않았다.
final class NoteClipView: NSClipView {
    override var documentRect: NSRect {
        var rect = super.documentRect
        guard let document = documentView else { return rect }
        let room = NoteOverscroll.bottom(bounds.height)
        rect.size.height = max(rect.height, document.frame.height + room)
        return rect
    }
}

class NoteTextView: NSTextView {
    private let content = NSTextContentStorage()
    var baseURL: URL?
    var openNote: (String) -> Void = { _ in }
    var linkOpener = OpenLinkAction()
    var linkName: (AppLink) -> String? = { _ in nil }
    // 한국어 입력 소스에서도 단축키가 바뀌지 않도록 키 코드로 받는다.
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

    var columnWidth: CGFloat { max(120, min(NoteLook.measure, bounds.width) - 2 * NoteLook.margin) }

    var column: ClosedRange<CGFloat> { textContainerOrigin.x...(textContainerOrigin.x + columnWidth) }

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

    // AppKit은 `NSTextInsertionIndicator`의 크기를 줄 전체 높이로 정하고, 캐럿이 한 번 움직일 때 여러 번 다시 정하며, 이를 막을 훅이 없다. 그래서 frame이 바뀔 때마다
    // 크기를 다시 맞춘다.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard let indicator = subview as? NSTextInsertionIndicator else { return }
        indicator.postsFrameChangedNotifications = true
        if let caretObserver { NotificationCenter.default.removeObserver(caretObserver) }
        caretObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: indicator, queue: nil) {
            [weak self, weak indicator] _ in
            MainActor.assumeIsolated {
                guard let self, let indicator, let storage = self.textStorage else { return }
                let fitted = NoteLines.caret(indicator.frame, at: self.selectedRange().location, in: storage)
                if fitted != indicator.frame { indicator.frame = fitted }
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
            let key = Self.letters[event.keyCode], shortcut?(key) == true
        {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func characterIndex(at point: NSPoint) -> Int? {
        guard let window, let storage = textStorage, storage.length > 0 else { return nil }
        let i = characterIndex(for: window.convertPoint(toScreen: convert(point, to: nil)))
        return i == NSNotFound || i >= storage.length ? nil : i
    }

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
        if let found = AppLink.link(in: storage.string, at: i) {
            linkOpener(found)
            return true
        }
        return false
    }

    func wikiLink(at i: Int) -> (link: WikiLink, range: NSRange)? {
        guard let storage = textStorage, i < storage.length, storage.attribute(.noteWiki, at: i, effectiveRange: nil) is String else {
            return nil
        }
        let text = storage.string as NSString
        let line = text.paragraphRange(for: NSRange(location: i, length: 0))
        let written = text.substring(with: line)
        guard let m = written.matches(of: WikiLink.pattern).first(where: { NSRange($0.range, in: written).contains(i - line.location) })
        else { return nil }
        let r = NSRange(m.range, in: written)
        return (WikiLink(m), NSRange(location: line.location + r.location, length: r.length))
    }

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

    // TextKit 2는 아직 배치하지 않은 텍스트의 높이를 추정하므로, 텍스트나 모양이 바뀐 뒤에는 같은 스크롤 오프셋에 다른 텍스트가 보인다. 그래서 바뀔 때마다 한 줄이 화면의 어디에 있었는지 적어 두고,
    // 바뀐 뒤에 그 자리로 되돌린다.

    var firstVisible: Int? {
        guard let manager = textLayoutManager,
            let fragment = manager.textLayoutFragment(for: CGPoint(x: 0, y: max(0, visibleRect.minY - textContainerOrigin.y)))
        else { return nil }
        return manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location)
    }

    func screenY(of index: Int) -> CGFloat? {
        guard let length = textStorage?.length, length > 0, let top = textLayoutManager?.top(of: max(0, min(index, length - 1))) else {
            return nil
        }
        return top + textContainerOrigin.y - visibleRect.minY
    }

    func place(_ index: Int, at y: CGFloat) {
        guard let scroll = enclosingScrollView, let length = textStorage?.length, length > 0,
            let top = textLayoutManager?.top(of: max(0, min(index, length - 1)))
        else { return }
        let target = max(0, top + textContainerOrigin.y - y)
        let clip = scroll.contentView
        if frame.height < target + clip.bounds.height { setFrameSize(NSSize(width: frame.width, height: target + clip.bounds.height)) }
        guard abs(clip.bounds.minY - target) > 0.5 else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: target))
        scroll.reflectScrolledClipView(clip)
    }

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
    private var revealing: Int?
    private var keeping: Int?
    var cards: NoteEmbedSource?
    var cardsRevision = 0
    private(set) var card: ReferenceCardPage?
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

    // 여기서 viewport를 다시 배치한다. 자리를 잡는 일은 스크롤만 하므로, 그려진 줄은 이전 배치의 자리에 남아 있었다. 다시 배치하면 TextKit이 아래쪽 높이를 고쳐 잡고 그 때문에 스크롤이 다시
    // 움직일 수 있으므로, 줄이 멈출 때까지 다시 둔다.
    private func placeKept() {
        guard let keeping else { return }
        for _ in 0..<4 {
            place(keeping, at: NoteLook.margin)
            textLayoutManager?.textViewportLayoutController.layoutViewport()
            guard let y = screenY(of: keeping), abs(y - NoteLook.margin) > 0.5 else { return }
        }
    }

    // 창은 휠 이벤트를 포인터 아래의 뷰로 보내는데, 노트 위에서는 말풍선의 스크롤 막대를 포함해 이 뷰가 받는다(`NoteScrollView.hitTest`). 노트로 올라가게 두면 말풍선에서 스크롤되는 수식
    // 위의 가로 스와이프가 아무 데도 가지 않았다. AppKit은 스와이프 하나를 한 뷰에 고정하므로, 스와이프가 시작한 곳이 그 스와이프 전체가 갈 곳을 정한다.
    override func scrollWheel(with event: NSEvent) {
        let starts = event.phase.contains(.began) || event.phase.contains(.mayBegin) || (event.phase.isEmpty && event.momentumPhase.isEmpty)
        if starts {
            wheelsBubble = bubble.map { $0.scrolls && $0.frame.contains(wheelPoint(event)) } ?? false
        }
        if wheelsBubble, let bubble {
            bubble.scroller.scrollWheel(with: event)
        } else {
            scrollNote(with: event)
        }
    }

    private var wheelsBubble = false

    func scrollNote(with event: NSEvent) {
        keeping = nil
        super.scrollWheel(with: event)
    }

    private func wheelPoint(_ event: NSEvent) -> NSPoint {
        guard event.window == nil, let window else { return convert(event.locationInWindow, from: nil) }
        return convert(window.convertPoint(fromScreen: event.locationInWindow), from: nil)
    }

    override func keyDown(with event: NSEvent) {
        keeping = nil
        hideCard()
        super.keyDown(with: event)
    }

    // 조합 중인 편집을 포함해 모든 변경 뒤에 스타일을 입힌다. 잠깐이라도 스타일 없이 두면 일반 텍스트의 12pt 글꼴로 보인다.
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

    private func matchTyping() {
        guard let storage = textStorage else { return }
        let caret = min(selectedRange().location, storage.length)
        // 앞의 텍스트는 윗줄의 것이고 `# 제목` 뒤에서 줄을 바꾸면 제목의 속성이라, 그대로 두면 이 줄을 제목 높이로 배치한다.
        if NoteLines.afterLastBreak(caret, in: storage) {
            typingAttributes = NoteLines.bodyLine
            return
        }
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: caret, length: 0))
        let at = caret > paragraph.location ? caret - 1 : min(caret, storage.length - 1)
        let around = storage.attributes(at: at, effectiveRange: nil)
        var typing: [NSAttributedString.Key: Any] = [.foregroundColor: NoteLook.text]
        for key in [NSAttributedString.Key.font, .paragraphStyle, .noteCaret] { typing[key] = around[key] }
        typingAttributes = typing
    }

    func load(_ text: String) {
        string = text
        undoManager?.removeAllActions(withTarget: self)
        restyle()
    }

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
        if selection.location >= NSMaxRange(range) {
            setSelectedRange(NSRange(location: selection.location + shift, length: selection.length))
        }
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
        if edit.range.length > 0 || !edit.text.isEmpty {
            guard shouldChangeText(in: edit.range, replacementString: edit.text) else { return }
            textStorage?.replaceCharacters(in: edit.range, with: edit.text)
            didChangeText()
        }
        setSelectedRange(edit.selection)
        if reveal { scrollRangeToVisible(selectedRange()) }
    }

    func textDidChange(_ notification: Notification) { onChange() }

    // 키 입력 없이 끝난 음절(다른 곳을 클릭하거나 다른 앱으로 간 경우)은 텍스트를 바꾸지 않으므로, 여기가 아니면 그 음절을 바인딩에 넘기는 곳이 없다.
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
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let top = self.topLine(lineStarts: self.lineStarts)
                self.onScroll(top.line, top.frac)
                self.placeMenu()
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
        apply(SourceEditing.tab(string as NSString, selectedRange(), back: false, catalog: catalog))
    }

    override func insertBacktab(_ sender: Any?) {
        apply(SourceEditing.tab(string as NSString, selectedRange(), back: true, catalog: catalog))
    }

    // 음절을 조합하는 동안에는 여기서 아무것도 하지 않는다. 그 키는 입력기의 것이고, 조합 중에 짝 기호를 닫거나 메뉴 항목을 고르면 음절이 갈라지거나 음절을 끝내는 키가 사라진다.

    override func insertText(_ text: Any, replacementRange: NSRange) {
        let typed = (text as? String) ?? (text as? NSAttributedString)?.string
        if !hasMarkedText(), let typed, replacementRange.location == NSNotFound || replacementRange == selectedRange(),
            let edit = SourceEditing.typed(typed, in: string as NSString, selection: selectedRange())
        {
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

    var caretFence: MathSyntax? {
        SourcePlace.at(selectedRange().location, in: string as NSString).fence.map { MathSyntax($0) }
    }

    @objc func showMathSymbols(_ sender: Any?) {
        let selection = selectedRange()
        guard !hasMarkedText(), selection.length == 0, SourcePlace.typing(at: selection.location, in: string as NSString).isMath else {
            return NSSound.beep()
        }
        insertText("\\", replacementRange: selection)
    }

    func refreshCompletion(opening: Bool) {
        guard !hasMarkedText() else { return }
        let selection = selectedRange()
        if selection.length == 0, let query = Completion.query(in: string as NSString, caret: selection.location, catalog: catalog),
            opening || completion.query.map({ Self.sameKind($0.kind, query.kind) }) == true
        {
            let items = Completion.items(for: query, catalog: catalog)
            if items.isEmpty, completion.more == nil || !CompletionMenu.late(query) {
                completion.hide()
            } else {
                completion.show(query, items)
            }
        } else {
            completion.hide()
        }
        if completion.visible { hideCard() }
        placeMenu()
    }

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
            if let own = taken.own {
                apply(own, reveal: false)
                if own.range.location <= query.range.location { query = query.shifted(by: own.text.utf16.count - own.range.length) }
            }
        }
        apply(Completion.edit(accepting: item, for: query, in: string as NSString))
        window?.makeFirstResponder(self)
        if query.kind == .slash || item.continues { refreshCompletion(opening: true) } else { placeMenu() }
    }

    func placeMenu() {
        guard completion.visible, let query = completion.query, let scroll = enclosingScrollView, let window else {
            menuHost?.isHidden = true
            return
        }
        let host =
            menuHost
            ?? {
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

    @objc func showInputGuide(_ sender: Any?) { openGuide() }

    // MARK: Tables

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, !hasMarkedText(), let shortcut = TableCommands.shortcut(of: event),
            let command = TableCommands.command(for: shortcut),
            let table = TableEditing.table(in: string as NSString, selection: selectedRange())
        {
            if let edit = table.edit(command) { apply(edit) } else { NSSound.beep() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        if let i = characterIndex(at: convert(event.locationInWindow, from: nil)), !NSLocationInRange(i, selectedRange()) {
            setSelectedRange(NSRange(location: i, length: 0))
        }
        guard let menu, let table = TableEditing.table(in: string as NSString, selection: selectedRange()) else { return menu }
        menu.insertItem(
            TableCommands.menu(for: table) { [weak self] edit in
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
        bubble?.hovered = false
        let point = convert(event.locationInWindow, from: nil)
        if let i = characterIndex(at: point) {
            if openLink(at: i, event: event) { return }
            if event.modifierFlags.intersection([.command, .shift, .option]).isEmpty, event.clickCount == 1, toggleTask(at: i) { return }
        }
        super.mouseDown(with: event)
    }

    func toggleTask(at i: Int) -> Bool {
        var box = NSRange()
        guard let done = textStorage?.attribute(.noteTask, at: i, effectiveRange: &box) as? Bool, box.length == 3 else { return false }
        let selection = selectedRange()
        apply(
            SourceEditing.Edit(range: NSRange(location: box.location + 1, length: 1), text: done ? " " : "x", caret: selection.location),
            reveal: false)
        setSelectedRange(selection)
        return true
    }

    // MARK: Block reference card

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
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

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        hideCard()
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        updateHint()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { hideCard() }
        super.viewWillMove(toWindow: newWindow)
    }

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

    // `characterIndex`는 줄 끝 너머나 열 옆에서도 가장 가까운 글자를 돌려주므로, 점이 그 글자의 상자 안에 있는지 확인해야 한다.
    private func reference(at point: NSPoint) -> (link: WikiLink, range: NSRange)? {
        guard let window, let i = characterIndex(at: point), let found = wikiLink(at: i), found.link.blockID != nil else { return nil }
        let box = convert(
            window.convertFromScreen(firstRect(forCharacterRange: NSRange(location: i, length: 1), actualRange: nil)), from: nil)
        return box.insetBy(dx: -Theme.Space.xxs, dy: -Theme.Space.xxs).contains(point) ? found : nil
    }

    private func showCard(_ link: WikiLink, range: NSRange) {
        guard let cards, let styler, hovered == range, !hasMarkedText(), !completion.visible, let scroll = enclosingScrollView,
            let content = HTMLRenderer.referenceCard(link, embeds: cards.embeds(revision: cardsRevision, text: string))
        else { return }
        let page = card ?? ReferenceCardPage()
        card = page
        if page.host.superview !== scroll { scroll.addSubview(page.host) }
        let width = min(columnWidth, scroll.bounds.width - 2 * Theme.Space.s)
        let tallest = (scroll.bounds.height / 2).rounded()
        page.load(content, math: styler.syntax.rawValue, accent: accent, baseURL: baseURL, width: width, maxHeight: tallest) {
            [weak self] height in
            guard let self, self.hovered == range, !self.hasMarkedText(), !self.completion.visible else { return }
            self.placeCard(page, range: range, size: CGSize(width: width, height: min(height, tallest)))
        }
    }

    private func placeCard(_ page: ReferenceCardPage, range: NSRange, size: CGSize) {
        guard let scroll = enclosingScrollView, let window else { return }
        let rect = { (i: Int) in
            scroll.convert(
                window.convertFromScreen(self.firstRect(forCharacterRange: NSRange(location: i, length: 1), actualRange: nil)), from: nil)
        }
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
        NoteMath.shared.host(in: self)
        return super.becomeFirstResponder()
    }

    var hintShown: Bool { hint.map { !$0.isHidden } ?? false }

    func updateHint() {
        let caret = selectedRange()
        guard window?.firstResponder === self, !hasMarkedText(), let window,
            SourceEditing.offersBlocks(in: string as NSString, selection: caret)
        else {
            hint?.isHidden = true
            return
        }
        let label =
            hint
            ?? {
                let label = HintLabel(
                    labelWithAttributedString: NSAttributedString(
                        string: String(localized: .notesGuideHint),
                        attributes: [
                            .font: NoteLook.font(NoteLook.body), .foregroundColor: NoteLook.text3,
                        ]))
                label.setAccessibilityElement(false)
                label.sizeToFit()
                addSubview(label)
                hint = label
                return label
            }()
        let size = label.fittingSize
        var line = convert(
            window.convertFromScreen(firstRect(forCharacterRange: NSRange(location: caret.location, length: 0), actualRange: nil)),
            from: nil)
        if line.height < 1 {
            line = NSRect(
                x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0), y: textContainerOrigin.y, width: 0,
                height: size.height)
        }
        label.frame = NSRect(x: line.minX + Theme.Space.xs, y: line.maxY - size.height, width: size.width, height: size.height)
        label.isHidden = false
    }

    func updateBubble() {
        let caret = selectedRange()
        var found: Rendering?
        if window?.firstResponder === self, caret.length == 0, let storage = textStorage, caret.location <= storage.length {
            found = rendering(at: caret.location, in: storage)
        }
        if let kept = bubble {
            if kept.scrolls, kept.hovered, found == nil || found?.image === kept.picture.image { return }
            if let found, found.image === kept.picture.image, found.size == kept.picture.frame.size,
                let origin = bubbleOrigin(kept.frame.size, found.span)
            {
                kept.setFrameOrigin(origin)
                kept.reveal(found.at, line: found.line)
                return
            }
        }
        bubble?.removeFromSuperview()
        bubble = nil

        guard let found else { return }
        let room = columnWidth
        let scale = found.math ? 1 : min(1, room / max(1, found.size.width))
        let view = PreviewBubble(
            image: found.image, size: CGSize(width: (found.size.width * scale).rounded(), height: (found.size.height * scale).rounded()),
            width: room + 2 * PreviewBubble.pad)
        guard let origin = bubbleOrigin(view.frame.size, found.span) else { return }
        view.setFrameOrigin(origin)
        view.onLeave = { [weak self] in self?.updateBubble() }
        addSubview(view)
        view.reveal(found.at, line: found.line)
        bubble = view
    }

    private func bubbleOrigin(_ size: CGSize, _ span: NSRange) -> NSPoint? {
        guard let window, let storage = textStorage, NSMaxRange(span) <= storage.length, span.length > 0 else { return nil }
        let text = storage.string as NSString
        var end = NSMaxRange(span)
        while end > span.location + 1, text.character(at: end - 1) == 0x0A { end -= 1 }
        let line = { (i: Int) in
            self.convert(
                window.convertFromScreen(self.firstRect(forCharacterRange: NSRange(location: i, length: 1), actualRange: nil)), from: nil)
        }
        let first = line(span.location), last = line(end - 1)
        let x = max(
            column.lowerBound - PreviewBubble.pad, min(first.minX - PreviewBubble.pad, column.upperBound + PreviewBubble.pad - size.width))
        let under = last.maxY + 4, over = first.minY - 4 - size.height
        // 정수 포인트에 둔다. 스크롤 막대의 clip view는 화면 픽셀에 맞춰 정렬하므로, 소수점 위치에서는 그림이 그만큼 밀렸다.
        return NSPoint(x: x.rounded(), y: (under + size.height <= visibleRect.maxY || over < visibleRect.minY ? under : over).rounded())
    }

    private struct Rendering {
        let image: NSImage
        let size: CGSize
        let span: NSRange
        let math: Bool
        let at: CGFloat
        var line: CGFloat?
    }

    private func redrawBubble() { updateBubble() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { NoteMath.shared.host(in: self, warm: true) }
    }

    private func rendering(at caret: Int, in storage: NSTextStorage) -> Rendering? {
        guard let styler, storage.length > 0 else { return nil }
        let at = { (span: NSRange) in CGFloat(caret - span.location) / CGFloat(max(1, span.length)) }
        let all = NSRange(location: 0, length: storage.length)
        var span = NSRange()
        if caret > 0 {
            if let tex = storage.attribute(.noteMath, at: caret - 1, longestEffectiveRange: &span, in: all) as? String,
                caret > span.location,
                let picture = NoteMath.shared.picture(
                    tex, syntax: styler.syntax, display: false, size: NoteLook.body, dark: styler.dark, trim: true,
                    ready: redrawBubble)
            {
                return Rendering(image: picture.image, size: picture.size, span: span, math: true, at: at(span))
            }
            if let source = storage.attribute(.noteImage, at: caret - 1, longestEffectiveRange: &span, in: all) as? String,
                caret > span.location,
                let image = NoteImages.load(source, base: baseURL)
            {
                let natural = image.size
                let scale = min(1, min(columnWidth, 480) / max(1, natural.width), 320 / max(1, natural.height))
                return Rendering(
                    image: image, size: CGSize(width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded()),
                    span: span, math: false, at: 0)
            }
        }
        if let tex = storage.attribute(.noteMathBlock, at: min(caret, storage.length - 1), longestEffectiveRange: &span, in: all)
            as? String,
            let picture = NoteMath.shared.picture(
                tex, syntax: storage.mathFence(at: span.location) ?? styler.syntax, display: true, size: NoteLook.body, dark: styler.dark,
                trim: true,
                ready: redrawBubble)
        {
            let place = Self.blockPlace(in: (storage.string as NSString).substring(with: span), at: caret - span.location)
            return Rendering(image: picture.image, size: picture.size, span: span, math: true, at: place.caret, line: place.line)
        }
        return nil
    }

    static func blockPlace(in source: String, at offset: Int) -> (caret: CGFloat, line: CGFloat) {
        let text = source as NSString
        var skip = IndexSet()
        let open = text.range(of: "$$"), close = text.range(of: "$$", options: .backwards)
        if open.location != NSNotFound { skip.insert(integersIn: open.location..<NSMaxRange(open)) }
        if close.location != NSNotFound, close.location >= NSMaxRange(open) { skip.insert(integersIn: close.location..<NSMaxRange(close)) }
        let blank = CharacterSet.whitespacesAndNewlines
        func ink(_ end: Int) -> Int {
            (0..<min(max(0, end), text.length)).count(where: { i in
                !skip.contains(i) && !(UnicodeScalar(text.character(at: i)).map { blank.contains($0) } ?? false)
            })
        }
        let total = CGFloat(max(1, ink(text.length)))
        let start = text.lineRange(for: NSRange(location: min(max(0, offset), text.length), length: 0)).location
        return (CGFloat(ink(offset)) / total, CGFloat(ink(start)) / total)
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
            let promises = board.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver], !promises.isEmpty
        {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            // folio:not-an-action a temporary folder for pasted files
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for promise in promises {
                promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: Self.promiseQueue) {
                    [weak self] url, error in
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

    private func insertFiles(from board: NSPasteboard, at index: Int) -> Bool {
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let links = urls.compactMap { url in (try? Data(contentsOf: url)).flatMap { saveFile(url.lastPathComponent, $0) } }
            guard !links.isEmpty else { return false }
            insertLinks(links, at: index)
            return true
        }
        guard board.string(forType: .string) == nil, let image = (board.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first,
            let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
            let link = saveFile("Pasted \(Date.now.formatted(.iso8601.dateSeparator(.dash).timeSeparator(.omitted))).png", png)
        else { return false }
        insertLinks([link], at: index)
        return true
    }

    private func insertLinks(_ links: [String], at index: Int) {
        let at = min(index, (string as NSString).length)
        let text = links.joined(separator: "\n")
        let lead =
            at > 0 && (string as NSString).substring(with: NSRange(location: at - 1, length: 1)) != "\n" && text.hasPrefix("!") ? "\n" : ""
        apply(
            SourceEditing.Edit(range: NSRange(location: at, length: 0), text: lead + text, caret: at + lead.utf16.count + text.utf16.count))
        window?.makeFirstResponder(self)
    }
}

final class HintLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PreviewBubble: NSView {
    static let pad = Theme.Space.m
    static let fade = 2 * Theme.Space.xl

    let picture: NSImageView
    let scroller: BubbleScroller
    let leading = EdgeFade(leading: true), trailing = EdgeFade(leading: false)
    var hovered = false
    var onLeave: (() -> Void)?
    let scrolls: Bool

    init(image: NSImage, size: CGSize, width: CGFloat) {
        let pad = Self.pad, border: CGFloat = 1
        let whole = CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad)
        let shown = CGSize(width: min(whole.width, max(width, 2 * pad)), height: whole.height)
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroller.contentView)
        scrolled()
    }

    required init?(coder: NSCoder) { fatalError() }

    func reveal(_ fraction: CGFloat, line: CGFloat? = nil) {
        guard scrolls, let document = scroller.documentView else { return }
        let visible = scroller.bounds.width
        let across = { (f: CGFloat) in self.picture.frame.minX + f * self.picture.frame.width }
        var x = across(fraction) - visible / 2
        if let line, across(fraction) <= across(line) + visible - 2 * Self.fade { x = across(line) - Self.fade }
        x = min(max(0, x), document.frame.width - visible)
        scroller.contentView.scroll(to: NSPoint(x: x.rounded(), y: 0))
        scroller.reflectScrolledClipView(scroller.contentView)
    }

    @objc private func scrolled() {
        let x = scroller.contentView.bounds.minX, end = (scroller.documentView?.frame.width ?? 0) - scroller.bounds.width
        leading.isHidden = !scrolls || x <= 0.5
        trailing.isHidden = !scrolls || x >= end - 0.5
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        scrolls && frame.contains(point) ? scroller : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseMoved(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { left() }

    func left() {
        guard hovered else { return }
        hovered = false
        onLeave?()
    }

    override var wantsUpdateLayer: Bool { true }

    // layer는 고정된 CGColor를 가진다. 여기서 뷰 자신의 appearance로 풀어야 테마가 바뀔 때 따라간다. init에서 풀면 그때의 appearance를 따라서, 라이트 창에 다크 말풍선이 떴다.
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NoteLook.card.cgColor
            layer?.borderColor = NoteLook.lineSoft.cgColor
        }
    }
}

final class BubbleScroller: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            // 노트의 스크롤로 바로 보낸다. responder chain으로 올리면 편집 보기로 돌아가고, 편집 보기는 말풍선 위의 휠을 다시 이 뷰로 넘긴다.
            if let note = superview?.superview as? SourceTextView {
                note.scrollNote(with: event)
            } else {
                nextResponder?.scrollWheel(with: event)
            }
            return
        }
        (superview as? PreviewBubble)?.hovered = true
        // `NSScrollView`가 처리하게 두지 않고 스와이프의 양만큼 직접 옮긴다. 노트의 scroll view 안에 들어 있고 편집 보기가 스와이프를 넘겨주는 상황에서는 `NSScrollView`가
        // 수식을 그대로 두었다. 휠 한 칸은 한 줄이다.
        guard let document = documentView else { return }
        let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * NoteLook.body
        let end = max(0, document.frame.width - contentView.bounds.width)
        contentView.scroll(to: NSPoint(x: min(max(0, contentView.bounds.minX - dx), end), y: 0))
        reflectScrolledClipView(contentView)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
}

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
        update(
            view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
            openLink: context.environment.openLink)
        return view
    }

    func updateUIView(_ view: SourceTextView, context: Context) {
        update(
            view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
            openLink: context.environment.openLink)
    }
}

class NoteTextView: UITextView {
    private let content = NSTextContentStorage()
    var baseURL: URL?
    var openNote: (String) -> Void = { _ in }
    var linkOpener = OpenLinkAction()
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
        // 노트 끝 아래의 여백은 content inset이라, 그대로 두면 UIKit이 스크롤 표시기도 그만큼 줄인다.
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
        if textContainerInset.left != inset {
            textContainerInset = UIEdgeInsets(top: NoteLook.margin, left: inset, bottom: NoteLook.margin, right: inset)
        }
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

// shortcut: iPad에서는 그림 붙여 넣기와 끌어 놓기, ⌘-클릭 링크, 상자로 할 일 체크, 수식과 그림을 그려 보이는 말풍선을 아직
// 지원하지 않는다. iPad로 노트를 쓰게 되면 더한다.
final class SourceTextView: NoteTextView, UITextViewDelegate {
    var onChange: () -> Void = {}
    var openGuide: @MainActor () -> Void = {}
    var onScroll: @MainActor (Int, Double) -> Void = { _, _ in }
    var saveFile: (String, Data) -> String? = { _, _ in nil }
    private var styler: SourceStyler?
    private var lineStarts: [Int] = [0]
    private var catalog = CompletionCatalog()
    private var assisting: (NoteAssist, MathSyntax)?
    private var revealing: Int?

    override init() {
        super.init()
        delegate = self
    }

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

    func setAssist(_ assist: NoteAssist, syntax: MathSyntax) {
        if let assisting, assisting.0 == assist, assisting.1 == syntax { return }
        assisting = (assist, syntax)
        catalog = assist.catalog(syntax: syntax)
    }

    var caretFence: MathSyntax? {
        SourcePlace.at(selectedRange.location, in: textStorage.string as NSString).fence.map { MathSyntax($0) }
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
        if selection.location >= NSMaxRange(range) {
            selectedRange = NSRange(location: selection.location + shift, length: selection.length)
        }
    }

    func insertAtCaret(_ text: String) {
        apply(SourceEditing.Edit(range: selectedRange, text: text, caret: selectedRange.location + text.utf16.count))
        becomeFirstResponder()
    }

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
            apply(SourceEditing.tab(source, range, back: false, catalog: catalog))
            return false
        }
        if text.isEmpty, range.length == 1, selectedRange.length == 0,
            let edit = SourceEditing.deleteBackward(in: source, selection: NSRange(location: NSMaxRange(range), length: 0))
        {
            apply(edit)
            return false
        }
        if let edit = SourceEditing.typed(text, in: source, selection: range) {
            apply(edit)
            return false
        }
        return true
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard markedTextRange == nil, NoteLines.afterLastBreak(selectedRange.location, in: textStorage) else { return }
        typingAttributes = NoteLines.bodyLine
    }

    // 표시된 텍스트(marked text)의 속성이 바뀌면 UIKit이 조합을 버린다.
    func textViewDidChange(_ textView: UITextView) {
        if markedTextRange == nil { restyle() }
        onChange()
    }

    // 키 입력 없이 끝난 음절(다른 곳을 탭하거나 앱을 떠난 경우)은 텍스트를 바꾸지 않으므로, `textViewDidChange`가 그 음절에 스타일을 입히거나 바인딩에 넘기지 않는다.
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

    @objc func showInputGuide(_ sender: Any?) { openGuide() }

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
    func top(of index: Int) -> CGFloat? {
        guard let location = location(documentRange.location, offsetBy: index) else { return nil }
        ensureLayout(for: NSTextRange(location: documentRange.location, end: location) ?? documentRange)
        return textLayoutFragment(for: location)?.layoutFragmentFrame.minY
    }
}
