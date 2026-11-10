import AppKit
import FolioDomain
import FolioMarkdown
import Foundation
import SwiftUI
import Testing
@testable import Folio

/// The write view: the markdown source styled in place, laid out by TextKit as in the app.
@MainActor @Suite(.serialized)
struct NoteSourceTests {
    static func editor(_ text: String, width: CGFloat = 900, dark: Bool = false) -> (SourceTextView, NSWindow) {
        let view = SourceTextView()
        view.delegate = view
        let window = NoteRender.host(view, width: width, dark: dark)
        view.baseURL = NoteRender.fixtures
        view.load(text)
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .latex, dark: dark)
        NoteRender.layout(view)
        return (view, window)
    }

    static var sample: String {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "fixtures/all-markdown.md")
        return Frontmatter.split((try? String(contentsOf: url, encoding: .utf8)) ?? "").body
    }

    /// The caret is one height on every body line, empty or holding smaller code, and stands over the text, not the
    /// whole line: the line's gap is above the text, and a caret through it reached up to the line before.
    @Test func linesAreOneHeightWithTheCaretOverTheText() throws {
        let text = "본문 줄\n\n`code` 섞인 줄\n> 인용\n## 제목\n끝"
        let (view, _) = Self.editor(text)
        let ns = text as NSString
        let body = try #require(NoteRender.caret(view, at: 0))
        let manager = try #require(view.textLayoutManager)
        let line = try #require(manager.textLayoutFragment(for: manager.documentRange.location)).layoutFragmentFrame
        #expect(body.height < line.height)
        for i in [ns.range(of: "\n\n").location + 1, ns.range(of: "섞인").location, ns.range(of: "인용").location, ns.range(of: "끝").location] {
            #expect(try #require(NoteRender.caret(view, at: i)).height == body.height)
        }
        #expect(try #require(NoteRender.caret(view, at: ns.range(of: "제목").location)).height > body.height)
        for word in ["본문", "섞인", "인용", "제목", "끝"] {
            let at = ns.range(of: word).location
            let caret = try #require(NoteRender.caret(view, at: at)), drawn = try #require(NoteRender.text(view, at: at))
            #expect(abs(caret.minY - drawn.lowerBound) <= 1 && abs(caret.maxY - drawn.upperBound) <= 1, "\(word): caret \(caret), text \(drawn)")
        }
    }

    /// The empty line under a heading is a body line, its caret as tall as body text's: at the note's end too, where
    /// the line holds no character and the caret took the heading's height from the line break before it.
    @Test(arguments: ["본문\n# 11-10(화)\n", "본문\n# 11-10(화)\n\n끝"])
    func theCaretUnderAHeadingIsABodyCaret(_ text: String) throws {
        let (view, _) = Self.typing(text)
        let ns = text as NSString
        let empty = text.hasSuffix("\n") ? ns.length : ns.range(of: "\n\n").location + 1
        view.setSelectedRange(NSRange(location: empty, length: 0))
        NoteRender.layout(view)
        let body = try #require(NoteRender.caret(view, at: 0))
        let heading = try #require(NoteRender.caret(view, at: ns.range(of: "11-10").location))
        let caret = try #require(NoteRender.caret(view, at: empty))
        #expect(heading.height > body.height)
        #expect(caret.height == body.height, "caret \(caret), body \(body)")
        #expect(caret.minY >= heading.maxY, "caret \(caret), heading \(heading)")
        #expect(view.typingAttributes[.noteCaret] as? CGFloat == body.height)
    }

    static func typing(_ text: String) -> (SourceTextView, NSWindow) {
        let (view, window) = editor(text)
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return (view, window)
    }

    /// ⌘-click anywhere on a link opens what it points at, the ID and block included, though its brackets and ID are
    /// styled apart from its name. The ID is dimmed like the brackets.
    @Test func aCommandClickOpensALinkByID() throws {
        let id = UUID()
        let text = "앞 [[note:\(id.uuidString)#^c1|매칭 정리]] 뒤 [[material:\(id.uuidString)#page=3]]"
        let (view, _) = Self.editor(text)
        var opened: [AppLink] = []
        view.linkOpener = OpenLinkAction { link, _, _ in opened.append(link) }
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let ns = text as NSString
        for word in ["매칭", "note:", "[[note", "page=3"] {
            #expect(view.openLink(at: ns.range(of: word).location + 1, event: click), "\(word)")
        }
        let note = AppLink(.note, id, anchor: .block("c1"))
        #expect(opened == [note, note, note, AppLink(.material, id, anchor: .page(3))])
        let color = { (i: Int) in view.textStorage?.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor }
        #expect(color(ns.range(of: id.uuidString).location) == NoteLook.text3 && color(ns.range(of: "매칭").location) != NoteLook.text3)
    }

    /// A copied address between brackets is the same link (#347), and a bare one opens without the sentence's full stop.
    @Test func aCommandClickOpensACopiedAddress() throws {
        let id = UUID()
        let text = "앞 [[folio://material/\(id.uuidString)#page=2]] 뒤 folio://exam/\(id.uuidString). 끝"
        let (view, _) = Self.editor(text)
        var opened: [AppLink] = []
        view.linkOpener = OpenLinkAction { link, _, _ in opened.append(link) }
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let ns = text as NSString
        for word in ["[[folio", "material/", "page=2", "exam/"] {
            #expect(view.openLink(at: ns.range(of: word).location + 1, event: click), "\(word)")
        }
        let page = AppLink(.material, id, anchor: .page(2))
        #expect(opened == [page, page, page, AppLink(.exam, id)])
        // The bare address reads as a link, as the preview draws it, without the full stop after it.
        let href = { (i: Int) in view.textStorage?.attribute(.noteHref, at: i, effectiveRange: nil) as? String }
        let exam = ns.range(of: "folio://exam/")
        #expect(href(exam.location) == AppLink(.exam, id).string && href(exam.location + AppLink(.exam, id).string.utf16.count) == nil)
    }

    static func size(_ view: NSTextView, at i: Int) -> CGFloat? {
        (view.textStorage?.attribute(.font, at: i, effectiveRange: nil) as? NSFont)?.pointSize
    }

    /// In the source only headings change the text size: code, math, task boxes and callout labels stay body size.
    @Test func onlyHeadingsChangeTheSize() throws {
        let (view, _) = Self.editor(Self.sample)
        let storage = try #require(view.textStorage)
        let ns = storage.string as NSString
        var odd: [String] = []
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, r, _ in
            let font = value as? NSFont
            // Monospaced type is scaled to read as the same size.
            let size = (font?.pointSize ?? 0) / (font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true ? NoteLook.monoScale : 1)
            let line = ns.substring(with: ns.lineRange(for: r))
            let heading = line.hasPrefix("#")
            if size != NoteLook.body, !(heading && NoteLook.headingSizes.contains(size)) { odd.append("\(size) \(ns.substring(with: r).debugDescription)") }
        }
        #expect(odd.isEmpty, "\(odd.prefix(5))")
    }

    /// A footnote's label takes the accent and its brackets are dimmed, in a reference and in a definition; a definition
    /// holding an address stays a footnote, not a link definition that turns every reference into a link.
    @Test func footnotesAreColoredAndNeverLinks() throws {
        let text = "주장[^src] 끝\n\n[^src]: https://example.com"
        let styler = SourceStyler(accent: CourseAccent.presets[0].accent, syntax: .latex, baseURL: nil, dark: false)
        let storage = styler.styled(text)
        let ns = text as NSString
        let color = { (i: Int) in storage.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor }
        let reference = ns.range(of: "[^src]")
        let definition = ns.range(of: "[^src]:", options: .backwards)
        for range in [reference, definition] {
            #expect(NoteAttributes.same(color(range.location + 2), CourseAccent.presets[0].accent.inkNative))
            #expect(NoteAttributes.same(color(range.location), NoteLook.text3))
            #expect(NoteAttributes.same(color(range.location + 5), NoteLook.text3))
        }
        #expect(storage.attribute(.noteHref, at: reference.location + 2, effectiveRange: nil) == nil)
    }

    @Test func hangulBeingComposedIsBodySized() throws {
        for text in ["- 하나", "본문", "## 제목"] {
            let (view, _) = Self.typing(text)
            view.insertNewline(nil)
            view.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(Self.size(view, at: view.markedRange().location) == NoteLook.body, "\(text)")
            view.unmarkText()
            #expect(Self.size(view, at: view.string.utf16.count - 1) == NoteLook.body, "\(text)")
        }
        let (view, _) = Self.typing("## 제목")
        view.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(Self.size(view, at: view.markedRange().location) == NoteLook.headingSizes[1])
    }

    /// The binding gets the text only once a syllable is done, so a SwiftUI update in between sees the editor ahead of it.
    @Test func aSyllableBeingComposedSurvivesTheEditorUpdating() throws {
        final class Box {
            var text = "가"
            var insert: String?
        }
        let box = Box()
        let editor = MarkdownEditor(text: Binding(get: { box.text }, set: { box.text = $0 }), baseURL: nil, math: .latex,
                                    insert: Binding(get: { box.insert }, set: { box.insert = $0 }), saveFile: { _, _ in nil }, openNote: { _ in })
        let coordinator = editor.makeCoordinator()
        let (view, window) = Self.editor(box.text)
        view.onChange = { coordinator.changed() }
        coordinator.view = view
        let accent = CourseAccent.presets[0].accent
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 1, length: 0))
        let none = NSRange(location: NSNotFound, length: 0)
        view.setMarkedText("ㄴ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
        editor.update(view, coordinator, accent: accent, dark: false)
        #expect(view.string == "가ㄴ" && view.hasMarkedText())
        view.setMarkedText("나", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
        editor.update(view, coordinator, accent: accent, dark: false)
        #expect(view.string == "가나")
        // Leaving the window ends the syllable without a keystroke.
        view.unmarkText()
        #expect(box.text == "가나")
    }

    /// Enter then Tab under `- 셋` starts a sub-item; CommonMark alone would make `셋` a heading until it has text.
    @Test func startingASubItemKeepsTheItemAbove() throws {
        let (view, _) = Self.typing("- 하나\n- 셋")
        view.insertNewline(nil)
        view.insertTab(nil)
        #expect(view.string == "- 하나\n- 셋\n    - ")
        let item = (view.string as NSString).range(of: "셋").location
        #expect(Self.size(view, at: item) == NoteLook.body)
        #expect(Self.size(view, at: item) == Self.size(view, at: (view.string as NSString).range(of: "하나").location))
        view.insertText("넷", replacementRange: view.selectedRange())
        #expect(Self.size(view, at: item) == NoteLook.body)
    }

    @Test func renderSample() {
        for dark in [false, true] {
            let (view, _) = Self.editor(Self.sample, dark: dark)
            NoteRender.write(view, "source-\(dark ? "dark" : "light")")
        }
    }

    /// Drawn under their line, a math block and an image made the note taller than its text, and the view couldn't
    /// scroll to a picture under the last line. Against the same source that renders nothing, the height is the same.
    @Test func mathBlocksAndImagesAddNoHeight() throws {
        func height(_ text: String) throws -> CGFloat {
            let (view, _) = Self.editor(text)
            return try #require(view.textLayoutManager).usageBoundsForTextContainer.height
        }
        let shown = try height("앞\n$$\nx^2\n$$\n![a](assets/sample.png)")
        let unshown = try height("앞\n$$\n\\frac{\n$$\n![a](assets/missing.png)")
        #expect(shown == unshown)
    }

    /// The math in the bubble is drawn after the caret comes to it (`NoteMath`), so it shows a moment later.
    static func bubble(_ view: SourceTextView) async -> PreviewBubble? {
        for _ in 0..<500 {
            if let bubble = view.subviews.compactMap({ $0 as? PreviewBubble }).first { return bubble }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    /// Off every screen but in the window list, as the math page draws only in a window that is.
    static func shown(_ window: NSWindow) {
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
    }

    @Test func theBubbleShowsMathBlocksAndImagesByTheCaret() async throws {
        let text = "앞 $y$\n$$\nx^2\n$$\n![a](assets/sample.png)"
        let (view, window) = Self.editor(text)
        Self.shown(window)
        defer { window.orderOut(nil) }
        window.makeFirstResponder(view)
        let ns = text as NSString
        func bubble(at i: Int) async -> PreviewBubble? {
            view.setSelectedRange(NSRange(location: i, length: 0))
            return await Self.bubble(view)
        }
        view.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(view.subviews.compactMap { $0 as? PreviewBubble }.isEmpty)
        #expect(await bubble(at: ns.range(of: "$y").location + 1) != nil)
        #expect(await bubble(at: ns.range(of: "x^2").location) != nil)
        // On the note's last line there's no room under it, so the bubble goes over it, where the view still shows it.
        let image = try #require(await bubble(at: ns.range(of: "sample").location))
        #expect(image.frame.maxY <= view.bounds.maxY && image.frame.minY >= 0, "\(image.frame) in \(view.bounds)")
    }

    @Test func renderDarkBubble() async {
        let text = "역행렬의 행렬식 $det(A^-1) = 1/det(A)$ 은 이렇다.\n\n둘째 줄"
        let (view, window) = Self.editor(text, width: 600, dark: true)
        Self.shown(window)
        defer { window.orderOut(nil) }
        view.drawsBackground = true
        view.backgroundColor = NoteLook.card
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .asciimath, dark: true)
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: (text as NSString).range(of: "det(A^").location, length: 0))
        _ = await Self.bubble(view)
        NoteRender.write(view, "bubble-dark")
    }

    /// The bubble pads its picture evenly, and the picture is the formula's ink (`NoteMathTests.picturesAreTheirInk`),
    /// so it hugs every shape of formula: a display formula's no wider than the formula, not the column, and one wider
    /// than the column is drawn at its size, scrolling in a bubble as wide as the column lets it be
    /// (`longMathScrollsInTheBubble`). All of them are written on one sheet for the PR.
    @Test func theMathBubbleHugsTheFormula() async throws {
        let columns: [(MathSyntax, Bool)] = [(.latex, false), (.latex, true), (.asciimath, false), (.asciimath, true)]
        for dark in [false, true] {
            var rows: [(String, [NSBitmapImageRep])] = []
            for shape in NoteMathTests.shapes {
                var cells: [NSBitmapImageRep] = []
                for (syntax, display) in columns {
                    let source = syntax == .latex ? shape.tex : shape.ascii
                    let text = display ? "앞\n$$\n\(source)\n$$\n뒤" : "앞 $\(source)$ 뒤"
                    let (view, window) = Self.editor(text, width: 720, dark: dark)
                    Self.shown(window)
                    defer { window.orderOut(nil) }
                    view.drawsBackground = true
                    view.backgroundColor = NoteLook.card
                    view.configure(accent: CourseAccent.presets[0].accent, syntax: syntax, dark: dark)
                    window.makeFirstResponder(view)
                    let ns = text as NSString
                    view.setSelectedRange(NSRange(location: display ? ns.range(of: source).location + 1 : ns.range(of: "$").location + 2, length: 0))
                    let label = "\(shape.name) \(syntax.rawValue) \(display ? "block" : "inline") \(dark ? "dark" : "light")"
                    let bubble = try #require(await Self.bubble(view), "\(label)")
                    let image = try #require(bubble.picture.image, "\(label)")
                    #expect(bubble.picture.frame.size == image.size, "\(label): \(bubble.picture.frame.size) for \(image.size)")
                    #expect(Self.inColumn(bubble, view), "\(label): \(bubble.frame) for \(view.column)")
                    if bubble.scrolls {
                        #expect(bubble.frame.width == view.columnWidth + 2 * PreviewBubble.pad, "\(label): \(bubble.frame.width) for \(view.columnWidth)")
                    } else {
                        let picture = bubble.convert(bubble.picture.bounds, from: bubble.picture)
                        let insets = [picture.minX, picture.minY, bubble.bounds.maxX - picture.maxX, bubble.bounds.maxY - picture.maxY]
                        #expect(insets.allSatisfy { $0 == PreviewBubble.pad }, "\(label): \(insets)")
                    }
                    // As wide as the bubble, and as tall as it and the line of source it's under, whole rather than
                    // cut through by the bubble's margin.
                    let closing = ns.range(of: "$", options: .backwards).location
                    let line = view.convert(window.convertFromScreen(view.firstRect(forCharacterRange: NSRange(location: closing, length: 1), actualRange: nil)), from: nil)
                    let top = min(bubble.frame.minY - 12, line.minY - 4), bottom = max(bubble.frame.maxY + 12, line.maxY + 4)
                    let around = CGRect(x: bubble.frame.minX - 12, y: top, width: bubble.frame.width + 24, height: bottom - top).intersection(view.bounds)
                    if let cell = Self.cell(view, bubble, around: around) {
                        cells.append(cell)
                    }
                }
                rows.append((shape.name, cells))
            }
            NoteRender.sheet(rows, columns: ["TeX 인라인", "TeX 블록", "AsciiMath 인라인", "AsciiMath 블록"], dark: dark,
                             "math-bubbles-\(dark ? "dark" : "light")")
        }
    }

    /// A formula wider than the column isn't shrunk into the bubble but scrolls in it, at its size: the bubble's as
    /// wide as the column lets it be, it scrolls by the picture's width, opens at the part the caret is in, fades at an
    /// edge the formula runs on past, and stays while the pointer is over it, for it to be scrolled. Its start and end
    /// are written on a sheet for the PR.
    @Test func longMathScrollsInTheBubble() async throws {
        let shape = try #require(NoteMathTests.shapes.first { $0.name == "긴 줄" })
        let columns: [(MathSyntax, Bool)] = [(.latex, false), (.latex, true), (.asciimath, false), (.asciimath, true)]
        for dark in [false, true] {
            var rows: [(String, [NSBitmapImageRep])] = []
            for (syntax, display) in columns {
                let source = syntax == .latex ? shape.tex : shape.ascii
                let text = display ? "앞\n$$\n\(source)\n$$\n뒤" : "앞 $\(source)$ 뒤"
                let (view, window) = Self.editor(text, width: 720, dark: dark)
                Self.shown(window)
                defer { window.orderOut(nil) }
                view.drawsBackground = true
                view.backgroundColor = NoteLook.card
                view.configure(accent: CourseAccent.presets[0].accent, syntax: syntax, dark: dark)
                window.makeFirstResponder(view)
                let ns = text as NSString, start = ns.range(of: source).location
                let label = "\(syntax.rawValue) \(display ? "block" : "inline") \(dark ? "dark" : "light")"
                view.setSelectedRange(NSRange(location: start + 1, length: 0))
                let bubble = try #require(await Self.bubble(view), "\(label)")
                let image = try #require(bubble.picture.image, "\(label)")
                let document = try #require(bubble.scroller.documentView, "\(label)")
                #expect(bubble.scrolls, "\(label)")
                #expect(bubble.picture.frame.size == image.size, "\(label): shrunk to \(bubble.picture.frame.size) from \(image.size)")
                #expect(bubble.frame.width == view.columnWidth + 2 * PreviewBubble.pad, "\(label): \(bubble.frame.width)")
                #expect(Self.inColumn(bubble, view), "\(label): \(bubble.frame) for \(view.column)")
                // The picture and its padding, inside the border.
                #expect(document.frame.width == image.size.width + 2 * (PreviewBubble.pad - 1), "\(label): \(document.frame.width) for \(image.size.width)")
                let end = document.frame.width - bubble.scroller.bounds.width
                func offset() -> CGFloat { bubble.scroller.contentView.bounds.minX }
                #expect(offset() == 0 && bubble.leading.isHidden && !bubble.trailing.isHidden, "\(label): opened at \(offset())")
                var cells = [try #require(Self.cell(view, bubble, around: Self.around(bubble, in: view)), "\(label)")]
                bubble.reveal(1)
                #expect(offset() == end && !bubble.leading.isHidden && bubble.trailing.isHidden, "\(label): \(offset()) for \(end)")
                cells.append(try #require(Self.cell(view, bubble, around: Self.around(bubble, in: view)), "\(label)"))
                rows.append(("\(syntax == .latex ? "TeX" : "AsciiMath") \(display ? "블록" : "인라인")", cells))
                // At the formula's end the caret opens it there, the same bubble scrolled rather than a new one.
                view.setSelectedRange(NSRange(location: start + 2, length: 0))
                bubble.reveal(0)
                view.setSelectedRange(NSRange(location: start + (source as NSString).length - 1, length: 0))
                #expect(view.bubble === bubble && offset() == end, "\(label): \(offset()) at the end")
                try await Self.wheelOver(bubble, in: view, label)
                // Under the pointer it stays as the caret leaves the formula, and goes when the pointer does.
                bubble.hovered = true
                view.setSelectedRange(NSRange(location: 0, length: 0))
                #expect(view.bubble === bubble, "\(label): gone while hovered")
                bubble.left()
                #expect(view.bubble == nil, "\(label): kept after the pointer left")
            }
            NoteRender.sheet(rows, columns: ["처음", "끝"], dark: dark, "math-bubble-scroll-\(dark ? "dark" : "light")")
        }
        try await multilineBlockScrolls()
        // A formula that fits has nothing to scroll: under the pointer or not, it goes with the caret, rather than
        // staying over the line the caret went to.
        let (view, window) = Self.editor("앞 $x^2$ 뒤", width: 720)
        Self.shown(window)
        defer { window.orderOut(nil) }
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 4, length: 0))
        let short = try #require(await Self.bubble(view))
        #expect(!short.scrolls)
        short.hovered = true
        view.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(view.bubble == nil)
    }

    /// A block written over several lines is one formula, as long as its lines together: at its size, in a bubble no
    /// wider than the column, opening at the caret's line from its start, and taking a wheel over it, which the note
    /// took before, so it couldn't be scrolled at all.
    func multilineBlockScrolls() async throws {
        let lines = ["det(B - tI) = det(Q^-1AQ - tI) = det(Q^-1(A-tI)Q) =",
                     "det(Q^-1)det(A - tI)det(Q) = 1/(det(Q)) det(A - tI) det(Q) =",
                     "det(A - tI)"]
        let text = "앞\n$$\n" + lines.joined(separator: "\n") + "\n$$\n뒤"
        let (view, window) = Self.editor(text, width: 720)
        Self.shown(window)
        defer { window.orderOut(nil) }
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .asciimath, dark: false)
        window.makeFirstResponder(view)
        let ns = text as NSString
        let open = ns.range(of: "$$").location, source = ns.substring(with: NSRange(location: open, length: ns.range(of: "뒤").location - open))
        view.setSelectedRange(NSRange(location: open + 1, length: 0))
        let bubble = try #require(await Self.bubble(view))
        let image = try #require(bubble.picture.image)
        let document = try #require(bubble.scroller.documentView)
        let visible = bubble.scroller.bounds.width, end = document.frame.width - visible
        func offset() -> CGFloat { bubble.scroller.contentView.bounds.minX }
        #expect(bubble.scrolls)
        #expect(bubble.picture.frame.size == image.size, "shrunk to \(bubble.picture.frame.size) from \(image.size)")
        #expect(document.frame.width == image.size.width + 2 * (PreviewBubble.pad - 1), "\(document.frame.width) for \(image.size.width)")
        #expect(bubble.frame.width == view.columnWidth + 2 * PreviewBubble.pad, "\(bubble.frame.width)")
        #expect(Self.inColumn(bubble, view), "\(bubble.frame) for \(view.column)")
        // On the `$$` line, the formula's start.
        #expect(offset() == 0 && bubble.leading.isHidden && !bubble.trailing.isHidden, "opened at \(offset())")
        // On the second line, that line's part from its start, the same bubble scrolled to it.
        let second = ns.range(of: lines[1]).location
        view.setSelectedRange(NSRange(location: second, length: 0))
        #expect(view.bubble === bubble)
        let line = SourceTextView.blockPlace(in: source, at: second - open).line
        let x = bubble.picture.frame.minX + line * bubble.picture.frame.width
        #expect(line > 0.2 && line < 0.6, "\(line)")
        #expect(offset() > 0 && x >= offset() && x <= offset() + visible, "line at \(x), shown from \(offset())")
        // On the last line, which ends the formula, and on the closing `$$`, its end.
        view.setSelectedRange(NSRange(location: ns.range(of: lines[2], options: .backwards).location + 4, length: 0))
        #expect(offset() == end, "\(offset()) for \(end)")
        view.setSelectedRange(NSRange(location: ns.range(of: "$$", options: .backwards).location + 1, length: 0))
        #expect(view.bubble === bubble && offset() == end, "\(offset()) for \(end) on the closing line")
        try await Self.wheelOver(bubble, in: view)
    }

    /// A wheel takes the window's way to the bubble: the window gives it to the view under the pointer, which over the
    /// note is the editor, and the editor hands a sideways one over the bubble to its scroller. Up or down, the note
    /// scrolls and the formula stays. The events are made in the app and sent to the editor; nothing reaches the screen.
    static func wheelOver(_ bubble: PreviewBubble, in view: SourceTextView, _ label: String = "") async throws {
        let scroll = try #require(view.enclosingScrollView as? NoteScrollView)
        let center = NSPoint(x: bubble.frame.midX, y: bubble.frame.midY)
        #expect(scroll.hitTest(try #require(scroll.superview).convert(center, from: view)) === view, "\(label)")
        func offset() -> CGFloat { bubble.scroller.contentView.bounds.minX }
        func note() -> CGFloat { scroll.contentView.bounds.minY }
        bubble.reveal(0)
        let (before, top) = (offset(), note())
        view.scrollWheel(with: try Self.wheel(x: -80, y: 0, at: center, in: view))
        for _ in 0..<50 where offset() <= before { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(offset() > before && note() == top, "\(label): sideways moved the formula \(before) → \(offset()), the note \(top) → \(note())")
        let sideways = offset()
        view.scrollWheel(with: try Self.wheel(x: 0, y: -80, at: center, in: view))
        for _ in 0..<50 where note() <= top { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(note() > top && offset() == sideways, "\(label): down moved the note \(top) → \(note()), the formula \(sideways) → \(offset())")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// A trackpad's scroll by `x` and `y` points over `point` in `view`, made in the app as AppKit gets one: with no
    /// window, at its place on the screen.
    static func wheel(x: Int32, y: Int32, at point: NSPoint, in view: NSView) throws -> NSEvent {
        let window = try #require(view.window)
        let screen = window.convertPoint(toScreen: view.convert(point, to: nil))
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0))
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(y))
        cg.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(x))
        // The screen's y runs down from the top of the main display, AppKit's up from its bottom.
        cg.location = CGPoint(x: screen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - screen.y)
        let event = try #require(NSEvent(cgEvent: cg))
        #expect(event.type == .scrollWheel && abs(event.scrollingDeltaX) >= abs(CGFloat(x)) / 2, "\(event)")
        return event
    }

    /// Within the text column, with the padding that puts the picture's start under its source's past it.
    static func inColumn(_ bubble: PreviewBubble, _ view: SourceTextView) -> Bool {
        bubble.frame.minX >= view.column.lowerBound - PreviewBubble.pad && bubble.frame.maxX <= view.column.upperBound + PreviewBubble.pad
    }

    /// A bubble, and the line of source it's under.
    static func around(_ bubble: PreviewBubble, in view: SourceTextView) -> CGRect {
        let frame = bubble.frame
        return CGRect(x: frame.minX - 12, y: frame.minY - 40, width: frame.width + 24, height: frame.height + 52).intersection(view.bounds)
    }

    /// The text around a bubble with the bubble over it, for the sheet. The bubble's layers are drawn here, scrolled as
    /// they are: `cacheDisplay` draws only what views draw, and the card, the picture and the fades are layers.
    static func cell(_ view: SourceTextView, _ bubble: PreviewBubble, around: CGRect) -> NSBitmapImageRep? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: around), let layer = bubble.layer,
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        view.cacheDisplay(in: around, to: rep)
        // The colors come in the window's display pass, which a window off every screen doesn't run; and `render(in:)`
        // draws a shadow unblurred, as a band under the card.
        for layered in [bubble, bubble.leading, bubble.trailing] as [NSView] { layered.updateLayer() }
        let shadow = layer.shadowOpacity
        layer.shadowOpacity = 0
        defer { layer.shadowOpacity = shadow }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        // The text view's y runs down, the layer's up.
        let cg = context.cgContext
        cg.translateBy(x: bubble.frame.minX - around.minX, y: around.maxY - bubble.frame.maxY)
        layer.render(in: cg)
        return rep
    }

    @Test func theBubbleTakesItsWindowsLook() throws {
        let card = { (name: NSAppearance.Name) -> CGColor? in
            var color: CGColor?
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance { color = NoteLook.card.cgColor }
            return color
        }
        for (look, other) in [(NSAppearance.Name.aqua, NSAppearance.Name.darkAqua), (.darkAqua, .aqua)] {
            let bubble = PreviewBubble(image: NSImage(size: NSSize(width: 20, height: 10)), size: CGSize(width: 20, height: 10), width: 400)
            bubble.appearance = NSAppearance(named: look)
            // Whatever the app's appearance is while the layer is updated, the bubble's own decides.
            NSAppearance(named: other)?.performAsCurrentDrawingAppearance { bubble.updateLayer() }
            #expect(bubble.layer?.backgroundColor == card(look))
        }
    }
}
