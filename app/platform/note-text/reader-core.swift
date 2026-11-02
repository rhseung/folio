import FolioDomain
import FolioMarkdown
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What the read view does with the note, the same on the Mac and the iPad: renders it, says which changes a block
/// takes, works out Enter, Backspace, marks and checkboxes, and writes typed blocks back.
@MainActor final class ReaderCore {
    /// A replacement the view makes in its own text, past the edit rules.
    struct Change {
        var range: NSRange
        var text: NSAttributedString
        var caret: Int
    }

    var edit: (@MainActor (Int, Int, String, String) -> Bool)?
    var builder: ReaderBuilder?
    private(set) var blocks: [ReaderBlock] = []
    /// The note as last rendered, and a newer one held back while a block is being typed into: rendering it then
    /// would drop the caret.
    private(set) var shown: String?
    private var pending: String?
    private var toggled: Set<Int> = []
    /// The block typed into since the last write.
    var dirty: Int?
    private var timer: Timer?
    let storage: NSTextStorage
    let widgets = ReaderWidgets()
    /// Called after the text is swapped for a new rendering.
    var rendered: () -> Void = {}
    /// Wraps swapping the text, so the view can keep its place on screen.
    var replacing: (() -> Void) -> Void = { $0() }
    /// Called after a block changed size in place.
    var resized: () -> Void = {}

    init(storage: NSTextStorage) {
        self.storage = storage
        widgets.resized = { [weak self] in self?.fit($0) }
    }

    /// The widget's block takes its page's new height in place: rendering the note again would drop a caret being
    /// typed with.
    private func fit(_ view: WidgetWebView) {
        guard let height = view.pageHeight else { return }
        var changed = false
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let widget = value as? WidgetAttachment, widget.view === view, widget.bounds.height != height else { return }
            widget.bounds.size.height = height
            storage.beginEditing()
            storage.edited(.editedAttributes, range: range, changeInLength: 0)
            storage.endEditing()
            changed = true
        }
        if changed { resized() }
    }

    func configure(accent: CourseAccent, syntax: MathSyntax, baseURL: URL?, dark: Bool, width: CGFloat) {
        let changed = builder.map { $0.accent != accent || $0.syntax != syntax || $0.dark != dark || $0.baseURL != baseURL || $0.width != width } ?? true
        builder = ReaderBuilder(accent: accent, syntax: syntax, baseURL: baseURL, dark: dark, width: width, widgets: widgets)
        if changed { rerender() }
    }

    func show(_ text: String, typing: Bool) {
        guard text != shown || pending != nil else { return }
        if typing, shown != nil {
            pending = text
        } else {
            render(text)
        }
    }

    func rerender() { if let shown { render(pending ?? shown) } }

    /// The block was left: what was typed is written, and a note held back is shown.
    func leave() {
        commit()
        if pending != nil { rerender() }
    }

    private func render(_ text: String) {
        guard var builder else { return }
        timer?.invalidate()
        dirty = nil
        pending = nil
        shown = text
        builder.toggled = toggled
        let result = builder.build(ParsedNote(text))
        blocks = result.blocks
        replacing { storage.setAttributedString(result.text) }
        rendered()
    }

    // MARK: What may change

    func block(at i: Int) -> Int? {
        guard storage.length > 0 else { return nil }
        return storage.attribute(.noteBlock, at: min(max(0, i), storage.length - 1), effectiveRange: nil) as? Int
    }

    func atom(at i: Int) -> (atom: NoteAtom, range: NSRange)? {
        guard i >= 0, i < storage.length else { return nil }
        var r = NSRange()
        guard let atom = storage.attribute(.noteAtom, at: i, longestEffectiveRange: &r, in: NSRange(location: 0, length: storage.length)) as? NoteAtom else { return nil }
        return (atom, r)
    }

    /// The block a change stays inside, if it may be typed into: never across blocks, into an atom, or over the line
    /// break that ends a block.
    func editableBlock(for range: NSRange) -> Int? {
        guard edit != nil, let b = block(at: range.location), b < blocks.count, blocks[b].editable,
              let span = ReaderBuilder.range(of: b, in: storage),
              range.location >= span.location, NSMaxRange(range) <= NSMaxRange(span) else { return nil }
        // Inside an atom only if the change takes all of it.
        for edge in [range.location, NSMaxRange(range)] {
            if let (_, r) = atom(at: edge), r.location < edge, edge < NSMaxRange(r) { return nil }
        }
        return b
    }

    /// Typing next to an atom, a checkbox or a list marker writes plain text, not more of it.
    func typingAttributes(at caret: Int) -> [NSAttributedString.Key: Any]? {
        guard storage.length > 0 else { return nil }
        let at = caret > 0 && (storage.string as NSString).character(at: caret - 1) != 0x0A ? caret - 1 : min(caret, storage.length - 1)
        var attributes = storage.attributes(at: at, effectiveRange: nil)
        let wasAtom = attributes[.noteAtom] != nil
        for key: NSAttributedString.Key in [.noteAtom, .attachment, .noteTask, .noteWiki, .noteCallout] { attributes[key] = nil }
        if wasAtom {
            attributes[.font] = NoteLook.font(NoteLook.body)
            attributes[.noteMarks] = 0
            attributes[.underlineStyle] = nil
            if attributes[.noteLink] == nil { attributes[.foregroundColor] = NoteLook.text }
        }
        return attributes
    }

    // MARK: Writing back

    func changed() {
        guard dirty != nil else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.commit() } }
    }

    /// Sends the block's new lines with the lines they replace; later blocks move here at once, for the next edit.
    func commit() {
        timer?.invalidate()
        guard let b = dirty, let edit, let range = ReaderBuilder.range(of: b, in: storage) else { return }
        dirty = nil
        let block = blocks[b]
        guard let text = ReaderMarkdown.block(storage, range, kind: block.kind, source: block.source, id: block.id), text != block.source else { return }
        guard edit(block.lines.lowerBound, block.lines.upperBound, block.source, text) else { return rerender() }
        // The page already shows the edit; when the note comes back with it, there's nothing to draw again.
        if var lines = shown?.components(separatedBy: "\n"), block.lines.upperBound <= lines.count {
            lines.replaceSubrange((block.lines.lowerBound - 1)...(block.lines.upperBound - 1), with: text.components(separatedBy: "\n"))
            shown = lines.joined(separator: "\n")
        }
        let count = { (s: String) in s.split(separator: "\n", omittingEmptySubsequences: false).count }
        let delta = count(text) - count(block.source)
        blocks[b].source = text
        blocks[b].lines = block.lines.lowerBound...(block.lines.upperBound + delta)
        for i in blocks.indices where i > b {
            blocks[i].lines = (blocks[i].lines.lowerBound + delta)...(blocks[i].lines.upperBound + delta)
        }
    }

    // MARK: Keys

    private func listItem(at i: Int) -> (info: ListInfo, line: NSRange, text: Int)? {
        guard let b = block(at: i), b < blocks.count, blocks[b].kind == .list else { return nil }
        let line = (storage.string as NSString).paragraphRange(for: NSRange(location: min(i, storage.length), length: 0))
        guard let info = storage.attribute(.noteListItem, at: line.location, effectiveRange: nil) as? ListInfo else { return nil }
        var text = line.location
        while let (a, r) = atom(at: text), a.source.isEmpty { text = NSMaxRange(r) }
        return (info, line, text)
    }

    /// Enter makes a line break in the same block, so twice leaves a blank line and starts a paragraph; in a list it
    /// makes the next item, and on an empty item takes it away, as leaving the list. Nil where Enter does nothing.
    func newline(_ selection: NSRange) -> Change? {
        guard let b = editableBlock(for: selection) else { return nil }
        dirty = b
        guard let item = listItem(at: selection.location) else {
            let attributes = typingAttributes(at: selection.location) ?? [:]
            return Change(range: selection, text: NSAttributedString(string: "\u{2028}", attributes: attributes), caret: selection.location + 1)
        }
        let end = NSMaxRange(item.line) - ((storage.string as NSString).substring(with: item.line).hasSuffix("\n") ? 1 : 0)
        if item.text == end, selection.length == 0 {
            guard item.line.location > 0, block(at: item.line.location - 1) == b else { return nil }
            return Change(range: NSRange(location: item.line.location - 1, length: end - item.line.location + 1), text: NSAttributedString(), caret: item.line.location - 1)
        }
        let head = storage.attributedSubstring(from: NSRange(location: item.line.location, length: item.text - item.line.location)).mutableCopy() as! NSMutableAttributedString
        var boxes: [NSRange] = []
        head.enumerateAttribute(.noteTask, in: NSRange(location: 0, length: head.length)) { value, r, _ in if value != nil { boxes.append(r) } }
        for r in boxes.reversed() {
            guard let builder else { break }
            head.replaceCharacters(in: r, with: ReaderBuilder.checkbox(false, accent: builder.accent, attributes: head.attributes(at: r.location, effectiveRange: nil)))
        }
        var lineBreak = storage.attributes(at: item.line.location, effectiveRange: nil)
        for key: NSAttributedString.Key in [.noteAtom, .attachment, .noteTask] { lineBreak[key] = nil }
        let next = NSMutableAttributedString(string: "\n", attributes: lineBreak)
        next.append(head)
        let info = ListInfo(depth: item.info.depth, ordered: item.info.ordered, number: item.info.number + 1, task: item.info.task)
        next.addAttribute(.noteListItem, value: info, range: NSRange(location: 0, length: next.length))
        // The new item's marker and checkbox are atoms of their own.
        next.enumerateAttribute(.noteAtom, in: NSRange(location: 1, length: next.length - 1)) { value, r, _ in
            if value != nil { next.addAttribute(.noteAtom, value: NoteAtom(""), range: r) }
        }
        if item.info.ordered {
            // The drawn number is only a guess until the note is shown anew; the markdown counts by position.
            let old = "\(item.info.number).\t"
            next.replaceCharacters(in: NSRange(location: 1, length: old.utf16.count),
                                   with: NSAttributedString(string: "\(item.info.number + 1).\t", attributes: next.attributes(at: 1, effectiveRange: nil)))
        }
        let rest = NSRange(location: NSMaxRange(selection), length: end - NSMaxRange(selection))
        let moved = storage.attributedSubstring(from: rest).mutableCopy() as! NSMutableAttributedString
        moved.addAttribute(.noteListItem, value: info, range: NSRange(location: 0, length: moved.length))
        let caret = selection.location + next.length
        next.append(moved)
        return Change(range: NSRange(location: selection.location, length: end - selection.location), text: next, caret: caret)
    }

    /// Backspace after an atom takes all of it, and at the start of an item joins it to the one above. Nil leaves it
    /// to the text view.
    func backspace(_ selection: NSRange) -> Change? {
        guard selection.length == 0, selection.location > 0 else { return nil }
        if let (a, r) = atom(at: selection.location - 1), !a.source.isEmpty {
            guard let b = editableBlock(for: r) else { return nil }
            dirty = b
            return Change(range: r, text: NSAttributedString(), caret: r.location)
        }
        guard let item = listItem(at: selection.location), item.text == selection.location else { return nil }
        guard item.line.location > 0, let b = editableBlock(for: NSRange(location: item.line.location - 1, length: 0)), block(at: item.line.location) == b else { return nil }
        dirty = b
        return Change(range: NSRange(location: item.line.location - 1, length: item.text - item.line.location + 1), text: NSAttributedString(), caret: item.line.location - 1)
    }

    /// ⌘B and ⌘I: the mark comes off if all of the selection has it, else goes on all of it. Returns false where it
    /// can't.
    func toggle(_ mark: InlineMarks, in range: NSRange) -> Bool {
        guard range.length > 0, let b = editableBlock(for: range) else { return false }
        if case .heading = blocks[b].kind { return false }
        var all = true
        storage.enumerateAttribute(.noteMarks, in: range) { value, _, _ in if !InlineMarks(rawValue: value as? Int ?? 0).contains(mark) { all = false } }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attributes, r, _ in
            var marks = InlineMarks(rawValue: attributes[.noteMarks] as? Int ?? 0)
            if all { marks.remove(mark) } else { marks.insert(mark) }
            storage.addAttribute(.noteMarks, value: marks.rawValue, range: r)
            if attributes[.noteAtom] == nil { storage.addAttribute(.font, value: Self.font(marks, like: attributes[.font] as? PlatformFont), range: r) }
        }
        storage.endEditing()
        dirty = b
        changed()
        return true
    }

    /// Typing attributes with `mark` switched, for typing on with no selection.
    static func toggled(_ mark: InlineMarks, _ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var a = attributes
        var marks = InlineMarks(rawValue: a[.noteMarks] as? Int ?? 0)
        marks.formSymmetricDifference(mark)
        a[.noteMarks] = marks.rawValue
        a[.font] = font(marks, like: a[.font] as? PlatformFont)
        return a
    }

    static func font(_ marks: InlineMarks, like font: PlatformFont?) -> PlatformFont {
        NoteLook.font(font?.pointSize ?? NoteLook.body, marks.contains(.strong) ? .semibold : .regular, italic: marks.contains(.emphasis), mono: marks.contains(.code))
    }

    // MARK: Taps

    enum Tap {
        case change(Change)
        case open(wiki: String?, href: String?)
        case handled
    }

    /// What a plain click or tap at `i` does, or nil for placing the caret.
    func tap(at i: Int, opensLinks: Bool) -> Tap? {
        guard i < storage.length else { return nil }
        let attributes = storage.attributes(at: i, effectiveRange: nil)
        if let index = attributes[.noteCallout] as? Int {
            toggled.formSymmetricDifference([index])
            rerender()
            return .handled
        }
        if let done = attributes[.noteTask] as? Bool, let (_, r) = atom(at: i), let builder, let b = editableBlock(for: r) {
            dirty = b
            return .change(Change(range: r, text: ReaderBuilder.checkbox(!done, accent: builder.accent, attributes: storage.attributes(at: r.location, effectiveRange: nil)),
                                  caret: NSMaxRange(r)))
        }
        // Where text can't be typed into, a link opens on a plain click, as on a page.
        let wiki = attributes[.noteWiki] as? String, href = attributes[.noteHref] as? String
        if wiki != nil || href != nil, opensLinks || editableBlock(for: NSRange(location: i, length: 0)) == nil { return .open(wiki: wiki, href: href) }
        return nil
    }

    // MARK: Following the editor

    /// Where to scroll, in text coordinates, for the editor's top line; `top` gives a character's line top.
    func follow(line: Int, frac: Double, top: (Int) -> CGFloat?) -> CGFloat {
        guard let i = blocks.lastIndex(where: { $0.lines.lowerBound <= line }), let a = ReaderBuilder.range(of: i, in: storage), let ya = top(a.location) else { return 0 }
        let next = i + 1 < blocks.count ? ReaderBuilder.range(of: i + 1, in: storage) : nil
        let yb = next.flatMap { top($0.location) } ?? (ya + 40)
        let from = blocks[i].lines.lowerBound, to = i + 1 < blocks.count ? blocks[i + 1].lines.lowerBound : from + 1
        return ya + (yb - ya) * min(1, (Double(line - from) + frac) / Double(max(1, to - from)))
    }
}

extension NSTextLayoutManager {
    /// The top of the line holding character `index`, laid out as far as there.
    func top(of index: Int) -> CGFloat? {
        guard let location = location(documentRange.location, offsetBy: index) else { return nil }
        ensureLayout(for: NSTextRange(location: documentRange.location, end: location) ?? documentRange)
        return textLayoutFragment(for: location)?.layoutFragmentFrame.minY
    }
}
