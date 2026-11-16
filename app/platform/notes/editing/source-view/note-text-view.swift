import FolioDomain
import FolioMarkdown
import SwiftUI

#if os(macOS)
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
#else
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
#endif
