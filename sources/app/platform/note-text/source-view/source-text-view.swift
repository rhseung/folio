import FolioDomain
import FolioMarkdown
import SwiftUI

#if os(macOS)
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
#else
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
