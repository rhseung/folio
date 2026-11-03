import AppKit
import FolioDomain
import FolioMarkdown
import Foundation
import SwiftMath
import Testing
@testable import Folio

/// The read view: the note rendered as text, typed into where a block writes back exactly as written.
@MainActor @Suite(.serialized)
struct NoteReaderTests {
    final class Edits {
        var all: [(from: Int, to: Int, old: String, new: String)] = []
    }

    static let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "fixtures")

    static func reader(_ text: String, width: CGFloat = 900, dark: Bool = false, edits: Edits? = nil) -> (ReaderTextView, NSWindow) {
        let view = ReaderTextView()
        view.delegate = view
        let window = NoteRender.host(view, width: width, dark: dark)
        view.baseURL = fixtures
        if let edits { view.edit = { edits.all.append(($0, $1, $2, $3)); return true } }
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .latex, dark: dark)
        view.show(text)
        NoteRender.layout(view)
        return (view, window)
    }

    @Test func renderSample() {
        for dark in [false, true] {
            let (view, _) = Self.reader(NoteSourceTests.sample, dark: dark, edits: Edits())
            NoteRender.write(view, "reader-\(dark ? "dark" : "light")")
        }
    }

    @Test func textSitsInTheMiddleOfItsLine() throws {
        let text = "> [!definition] Matching\n> A set of edges.\n\n본문 `code` 와 $x^2$ 끝\n\n```python\nx = 1\n```"
        let (view, _) = Self.reader(text)
        let shown = view.string as NSString
        for word in ["Matching", "A set", "본문", "PYTHON"] {
            let gaps = try #require(NoteRender.gaps(view, at: shown.range(of: word).location))
            #expect(abs(gaps.above - gaps.below) <= 1, "\(word): \(gaps)")
        }
        let body = try #require(NoteRender.caret(view, at: shown.range(of: "A set").location))
        #expect(try #require(NoteRender.caret(view, at: shown.range(of: "본문").location)).height == body.height)
    }

    @Test func aCalloutThatEndsTheNoteBoxesItsLastLine() throws {
        let (view, _) = Self.reader("> [!definition] Matching\n> A set of pairwise non-adjacent edges.\n")
        let manager = try #require(view.textLayoutManager)
        var last: NoteFragment?
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) {
            last = $0 as? NoteFragment ?? last
            return true
        }
        let fragment = try #require(last)
        let box = try #require(fragment.boxRect)
        let line = try #require(fragment.textLineFragments.last).typographicBounds
        #expect(box.minY <= line.minY && box.maxY > line.maxY)
    }

    @Test func aNestedQuoteKeepsTheOuterBoxAndAddsASpine() throws {
        let (view, _) = Self.reader("> 바깥\n> > 안쪽\n> > > 더 안쪽\n>\n> 다시 바깥")
        let storage = try #require(view.textStorage)
        let shown = storage.string as NSString
        for (word, spines) in [("바깥", 0), ("안쪽", 1), ("더 안쪽", 2), ("다시 바깥", 0)] {
            let at = shown.range(of: word).location
            #expect(storage.attribute(.noteBox, at: at, effectiveRange: nil) is NoteBox, "\(word)")
            #expect((storage.attribute(.noteQuotes, at: at, effectiveRange: nil) as? [NoteBox])?.count ?? 0 == spines, "\(word)")
        }
        // Only a paragraph's gap above a nested quote, not a block's.
        let style = try #require(storage.attribute(.paragraphStyle, at: shown.range(of: "안쪽").location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.paragraphSpacingBefore == 0)
    }

    @Test func mermaidDrawsAsAPictureAndFallsBackToItsSource() throws {
        let (view, _) = Self.reader("```mermaid\ngraph TD\n    A[시작] --> B[끝]\n```\n\n```mermaid\n이건 다이어그램이 아니다\n```")
        let storage = try #require(view.textStorage)
        let picture = try #require(storage.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        #expect(picture.bounds.width > 20 && picture.bounds.height > 40)
        // One that doesn't parse shows as code, not an empty picture.
        #expect(Self.codes(storage).contains { $0.code.string.contains("이건 다이어그램이 아니다") })
    }

    @Test func codeColorsCallsAndSwift() {
        let colored = { (code: String, language: String, word: String) -> Bool in
            let at = (code as NSString).range(of: word)
            return NoteScripts.highlight(code, language: language).contains { NSIntersectionRange($0.range, at).length > 0 && NoteLook.token($0.classes) != nil }
        }
        #expect(colored("def f(g):\n    return len(g)", "python", "len"))
        #expect(colored("def f(g):\n    return len(g)", "python", " f("))
        #expect(colored("let edges: [Int] = []", "swift", "let"))
        #expect(colored("@dataclass\nclass G:\n    pass", "python", "dataclass"))
        // A property and a called method on it read differently.
        let line = "g.adj.get(u)"
        let looks = NoteScripts.highlight(line, language: "python").compactMap { t in NoteLook.token(t.classes).map { (t.range, $0.color) } }
        let color = { (word: String) in looks.first { NSIntersectionRange($0.0, (line as NSString).range(of: word)).length > 0 }?.1 }
        #expect(color("adj") != nil && color("get") != nil && color("adj") != color("get"))
    }

    static func codes(_ storage: NSAttributedString) -> [CodeAttachment] {
        var found: [CodeAttachment] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let code = value as? CodeAttachment { found.append(code) }
        }
        return found
    }

    @Test func aLongCodeLineScrollsInsteadOfWrapping() throws {
        let long = "x = [" + (1...80).map(String.init).joined(separator: ", ") + "]"
        let (view, _) = Self.reader("```python\nx = 1\n```\n\n```python\n\(long)\n```", width: 600)
        let codes = Self.codes(try #require(view.textStorage))
        try #require(codes.count == 2)
        #expect(codes[1].bounds.height == codes[0].bounds.height)
        #expect(codes[1].bounds.width < 600)
        let scroll = try #require(codes[1].view as? NSScrollView)
        #expect((scroll.documentView?.frame.width ?? 0) > scroll.frame.width)
        // The text view places it over its attachment, since AppKit never asks for an attachment's view.
        #expect(scroll.superview === view && !scroll.isHidden)
        // Its scroller sits in the box's padding, under the last line rather than over it.
        scroll.tile()
        let scroller = try #require(scroll.horizontalScroller).frame
        let lines = codes[1].bounds.height
        #expect(scroll.isFlipped ? scroller.minY >= lines : scroller.maxY <= scroll.frame.height - lines, "\(scroller) \(lines) \(scroll.frame)")
    }

    @Test func aTickedBoxIsAsBigAsAnEmptyOne() throws {
        // The extent of what's drawn, so a fill that stops short of the empty box's border shows.
        func inked(_ done: Bool) throws -> CGRect {
            let s = ReaderBuilder.checkbox(done, accent: CourseAccent.presets[0].accent, attributes: [:])
            let image = try #require((s.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)?.image)
            let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
            NSGraphicsContext.restoreGraphicsState()
            var box = CGRect.null
            for x in 0..<64 { for y in 0..<64 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { box = box.union(CGRect(x: x, y: y, width: 1, height: 1)) } }
            return box
        }
        #expect(try inked(true) == inked(false))
    }

    @Test func mathKeepsInkThatLeavesItsBox() throws {
        func ink(_ image: NSImage) throws -> CGSize {
            let scale: CGFloat = 2, pad: CGFloat = 40
            let w = Int((image.size.width + 2 * pad) * scale), h = Int((image.size.height + 2 * pad) * scale)
            let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = NSSize(width: CGFloat(w) / scale, height: CGFloat(h) / scale)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: CGPoint(x: pad, y: pad), size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            var box = CGRect.null
            for x in 0..<w { for y in 0..<h where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 { box = box.union(CGRect(x: x, y: y, width: 1, height: 1)) } }
            return box.size
        }
        for tex in [#"G - T"#, #"\bar S"#, #"\|T\| \ge \|\kappa\|"#, #"f"#] {
            let picture = try #require(NoteMath.picture(tex, syntax: .latex, display: false, size: 16, color: .black, dark: false))
            // SwiftMath's own picture with room on every side: all the ink the formula has.
            let whole = MTMathImage(latex: tex, fontSize: 16, textColor: .black, labelMode: .text)
            whole.contentInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            let reference = try #require(whole.asImage().1)
            let (got, want) = (try ink(picture.image), try ink(reference))
            // A pixel either way is antialiasing: the two are drawn at different fractions of a point.
            #expect(abs(got.width - want.width) <= 1 && abs(got.height - want.height) <= 1, "\(tex): \(got) vs \(want)")
        }
    }

    @Test func aTaskShowsItsBoxWithoutABullet() {
        let (view, _) = Self.reader("- [ ] 할 일\n- [x] 한 일\n- [ ]\n- 그냥 항목\n\n1. [ ] 번호 할 일")
        let lines = view.string.components(separatedBy: "\n")
        #expect(lines.filter { $0.hasPrefix("•") }.count == 1)
        #expect(lines.contains { $0.hasPrefix("1.") })
    }

    @Test func aCalloutFoldsWithAChevron() {
        let (view, _) = Self.reader("> [!note]- 접힘\n> 안")
        #expect(!view.string.contains("›") && !view.string.contains("⌄"))
        #expect(view.textStorage?.attribute(.attachment, at: view.string.utf16.count - 1, effectiveRange: nil) != nil
            || view.textStorage?.attribute(.attachment, at: view.string.utf16.count - 2, effectiveRange: nil) != nil)
    }

    /// Text, marks, links, wikilinks, math and lists write back as written, so they can be typed into; a block whose
    /// markdown would come back different (`_x_` for `*x*`) stays read-only.
    @Test func blocksThatWriteBackExactlyAreEditable() {
        let text = """
        # 제목 *기울임*

        문단 *기울임* **굵게** ~~취소~~ `code` [링크](https://example.com) [[노트|별칭]] $x^2$ 끝 ^abc
        둘째 줄

        - 하나
            - 둘 **굵게**
        - [ ] 할 일
        - [x] 한 일

        1. 첫째
        2. 둘째

        _밑줄 기울임_

        > 인용
        """
        let (view, _) = Self.reader(text, edits: Edits())
        #expect(view.blocks.map(\.editable) == [true, true, true, true, false, false])
    }

    @Test func typingCommitsTheBlocksLines() throws {
        let edits = Edits()
        let (view, window) = Self.reader("# 제목\n\n첫 문단\n\n둘째 문단", edits: edits)
        window.makeFirstResponder(view)
        let storage = try #require(view.textStorage)
        let end = try #require(ReaderBuilder.range(of: 2, in: storage))
        view.setSelectedRange(NSRange(location: NSMaxRange(end), length: 0))
        view.insertText(" 더", replacementRange: view.selectedRange())
        view.insertNewline(nil)
        view.insertText("새 줄", replacementRange: view.selectedRange())
        window.makeFirstResponder(nil)
        #expect(edits.all.count == 1)
        #expect(edits.all.first.map { [String($0.from), String($0.to), $0.old, $0.new] } == ["5", "5", "둘째 문단", "둘째 문단 더\n새 줄"])
    }

    /// A line's height with the gap under it, which a paragraph holding a tall picture keeps as line spacing.
    static func lineHeight(_ view: NSTextView, at offset: Int) -> CGFloat? {
        guard let manager = view.textLayoutManager,
              let location = manager.location(manager.documentRange.location, offsetBy: offset),
              let fragment = manager.textLayoutFragment(for: location) else { return nil }
        let inFragment = offset - manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location)
        let gap = (view.textStorage?.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing ?? 0
        return fragment.textLineFragments.first { NSLocationInRange(inFragment, $0.characterRange) }.map { $0.typographicBounds.height + gap }
    }

    /// A picture far taller than the text gets a line of its own height, wherever it's written in the paragraph, and the
    /// text's lines keep theirs.
    @Test(arguments: [
        ("![그림](assets/sample.png)\n첫 줄\n둘째 줄", ["첫 줄", "둘째 줄"]),
        ("첫 줄\n둘째 줄\n![그림](assets/sample.png)", ["첫 줄", "둘째 줄"]),
        ("앞 글 ![그림|2000](assets/sample.png)", ["앞 글"]),
        ("[![그림](assets/sample.png)](https://example.com)\n설명", ["설명"]),
        ("*![그림](assets/sample.png)*\n설명", ["설명"]),
    ])
    func textByAPictureKeepsItsOwnLineHeight(source: String, words: [String]) throws {
        let (view, _) = Self.reader(source + "\n\n보통 문단", edits: Edits())
        let shown = view.string as NSString
        let plain = try #require(Self.lineHeight(view, at: shown.range(of: "보통 문단").location))
        for word in words {
            #expect(Self.lineHeight(view, at: shown.range(of: word).location) == plain, "\(word) in \(source.debugDescription)")
        }
        let picture = shown.range(of: "\u{FFFC}").location
        #expect(try #require(Self.lineHeight(view, at: picture)) > 2 * plain)
    }

    /// Unbounded, a picture's line took no gap, so the text under it sat closer than any two lines of text; and a
    /// paragraph of pictures alone fixed every line to the tallest, so a small picture under a big one stood as tall.
    @Test func aPicturesLineKeepsTheGapAndAShortPictureItsHeight() throws {
        let (view, _) = Self.reader("![큰 그림](assets/sample.png)\n첫 줄\n\n![큰 그림](assets/sample.png)\n![작은 그림|40](assets/sample.png)")
        let manager = try #require(view.textLayoutManager)
        var fragments: [NSTextLayoutFragment] = []
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: []) { fragments.append($0); return true }
        let gap = try #require((view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineSpacing)
        #expect(gap > 0)
        let text = fragments[0].textLineFragments
        #expect(text.count == 2 && text[1].typographicBounds.minY - text[0].typographicBounds.maxY == gap)
        let pictures = fragments[1].textLineFragments
        #expect(pictures.count == 2 && pictures[1].typographicBounds.height < pictures[0].typographicBounds.height / 2)
    }

    /// A picture, formula or table alone in its paragraph has no shorter line to keep; freed like one beside text, its
    /// line lost the room above it and the block sat high, unlike a smaller one.
    @Test(arguments: ["![그림](assets/sample.png)", "$$\\begin{pmatrix} 1 \\\\ 2 \\\\ 3 \\\\ 4 \\end{pmatrix}$$", "| 가 |\n| --- |\n| 나 |\n| 다 |\n| 라 |"])
    func aBlockAloneKeepsItsFixedLine(source: String) throws {
        let (view, _) = Self.reader("앞\n\n" + source + "\n\n뒤")
        let storage = try #require(view.textStorage)
        let at = (storage.string as NSString).range(of: "\u{FFFC}").location
        #expect(at != NSNotFound)
        let style = try #require(storage.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.maximumLineHeight == style.minimumLineHeight && style.lineSpacing == 0, "\(source)")
    }

    /// By a tall picture a line is shorter by the gap kept under it. Centered on the full height, its text sat half the
    /// gap under the middle of the line, and the caret and selection, which follow the line, stood above the text.
    @Test func textByAPictureStandsInTheMiddleOfItsLine() throws {
        let (view, _) = Self.reader("앞\n\n첫 줄\n![그림](assets/sample.png)\n끝 줄\n\n뒤")
        let shown = view.string as NSString
        for word in ["첫 줄", "끝 줄"] {
            let at = shown.range(of: word).location
            let gaps = try #require(NoteRender.gaps(view, at: at))
            #expect(abs(gaps.above - gaps.below) <= 1, "\(word): \(gaps)")
        }
    }

    @Test func aParagraphWithAPictureStillWritesBack() throws {
        let edits = Edits()
        let source = "![그림](assets/sample.png)\n첫 줄\n둘째 줄"
        let (view, window) = Self.reader(source + "\n\n보통 문단", edits: edits)
        NoteRender.write(view, "reader-picture-text")
        #expect(view.blocks.map(\.editable) == [true, true])
        window.makeFirstResponder(view)
        let storage = try #require(view.textStorage)
        let end = try #require(ReaderBuilder.range(of: 0, in: storage))
        view.setSelectedRange(NSRange(location: NSMaxRange(end), length: 0))
        view.insertText(" 끝", replacementRange: view.selectedRange())
        window.makeFirstResponder(nil)
        #expect(edits.all.first?.new == source + " 끝")
    }

    static let wideMath = """
    where $\\tilde{A}_{1j}$: the $(n-1) \\times (n-1)$ matrix obtained from A by deleting the 1st row and the jth column of it.

    Ex. Let

    $$A = \\begin{pmatrix} 2 & 0 & 0 & 1 \\\\ 0 & 1 & 0 & 0 \\\\ 1 & 0 & -1 & 0 \\\\ 1 & 1 & 1 & 1 \\end{pmatrix} \\det(A) = (-1)^{1+1} \\cdot 2 \\cdot \\det\\begin{pmatrix} 1 & 0 & 0 \\\\ 0 & -1 & 0 \\\\ 1 & 1 & 1 \\end{pmatrix} + (-1)^{1+2} \\cdot 0 \\cdot \\det\\begin{pmatrix} 0 & 0 & 0 \\\\ 1 & -1 & 0 \\\\ 1 & 1 & 1 \\end{pmatrix} + (-1)^{1+3} \\cdot 0 \\cdot 0$$

    Then the last line.
    """

    /// Wider than the column, a formula scrolls on its own; left in the text, TextKit moved the whole page over to show
    /// it and cut off the end of every other line.
    @Test func aWideFormulaScrollsInsteadOfMovingThePage() throws {
        let (view, _) = Self.reader(Self.wideMath, width: 600)
        NoteRender.write(view, "reader-wide-math")
        let shown = view.string as NSString
        let first = try #require(NoteRender.caret(view, at: shown.range(of: "where").location))
        let last = try #require(NoteRender.caret(view, at: shown.range(of: "Then").location))
        let padding = try #require(view.textContainer).lineFragmentPadding
        #expect(first.minX == padding && last.minX == padding, "\(first) \(last)")
        let scroll = try #require(view.subviews.compactMap { $0 as? NSScrollView }.first)
        #expect(scroll.frame.width == view.lineWidth)
        #expect(try #require(scroll.documentView).frame.width > view.lineWidth)
        #expect(scroll.frame.minX >= view.textContainerOrigin.x - 1)
    }

    /// The bubble over a math block is shrunk to the editor and lets a click through to the lines under it.
    @Test func aWideFormulasBubbleFitsAndTakesNoClicks() throws {
        let (view, window) = NoteSourceTests.editor(Self.wideMath, width: 600)
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "pmatrix").location, length: 0))
        NoteRender.write(view, "source-wide-math")
        let bubble = try #require(view.subviews.compactMap { $0 as? PreviewBubble }.first)
        #expect(bubble.frame.width <= view.visibleRect.width)
        #expect(bubble.hitTest(NSPoint(x: bubble.frame.midX, y: bubble.frame.midY)) == nil)
    }

    /// Everything that can be wider than the column, at the top and inside lists, quotes and callouts.
    static let wideThings = """
    # 제목 $\\sum_{i=1}^{n} a_i b_i c_i d_i e_i f_i g_i h_i i_i j_i k_i l_i m_i n_i o_i p_i q_i r_i s_i t_i u_i$

    인라인 $\\sum_{i=1}^{n} a_i b_i c_i d_i e_i f_i g_i h_i i_i j_i k_i l_i m_i n_i o_i p_i q_i r_i s_i t_i u_i v_i w_i x_i$ 끝

    ![넓은|2000](assets/sample.png)

    https://example.com/a/very/long/link/that/has/no/spaces/anywhere/in/it/and/keeps/going/and/going/until/it/is/wider/than/any/column

    | 하나 | 둘 | 셋 | 넷 | 다섯 | 여섯 | 일곱 | 여덟 | 아홉 | 열 | 열하나 | 열둘 |
    | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
    | 아주 긴 칸의 글 | $\\int_0^1 x^2 \\, dx = \\frac{1}{3}$ | 셋 | 넷 | 다섯 | 여섯 | 일곱 | 여덟 | 아홉 | 열 | 열하나 | 열둘 |

    - 목록 ![넓은|2000](assets/sample.png)
        - 하위 $\\sum_{i=1}^{n} a_i b_i c_i d_i e_i f_i g_i h_i i_i j_i k_i l_i m_i n_i o_i p_i q_i r_i s_i$
        - 표 아래

          | 하나 | 둘 | 셋 | 넷 | 다섯 | 여섯 | 일곱 | 여덟 | 아홉 | 열 |
          | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
          | 아주 긴 칸의 글 | 둘 | 셋 | 넷 | 다섯 | 여섯 | 일곱 | 여덟 | 아홉 | 열 |

          $$\\sum_{i=1}^{n} a_i b_i c_i d_i e_i f_i g_i h_i i_i j_i k_i l_i m_i n_i o_i p_i q_i r_i s_i t_i u_i v_i w_i x_i y_i z_i$$

    > 인용 ![넓은|2000](assets/sample.png)
    > > 안쪽 인용 ![넓은|2000](assets/sample.png)
    > > $$\\sum_{i=1}^{n} a_i b_i c_i d_i e_i f_i g_i h_i i_i j_i k_i l_i m_i n_i o_i p_i q_i r_i s_i t_i u_i v_i w_i x_i$$

    > [!note] 콜아웃
    > ![넓은|2000](assets/sample.png)
    >
    > | 하나 | 둘 | 셋 | 넷 | 다섯 | 여섯 | 일곱 | 여덟 | 아홉 | 열 | 열하나 | 열둘 |
    > | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
    > | 아주 긴 칸의 글 | 둘 | 셋 | 넷 | 다섯 | 여섯 | 일곱 | 여덟 | 아홉 | 열 | 열하나 | 열둘 |
    >
    > ```swift
    > let x = "a very long line of code that goes on and on and on past the edge of any column at all"
    > ```
    """

    /// Each picture that reaches past the room its paragraph gives it, between the paragraph's indents. A line's own
    /// bounds stay inside the column even when a picture on it doesn't, so pictures are measured one by one. Past the
    /// column, TextKit moves the whole page over to show one; past an indent, it runs out of its quote or callout box.
    static func overflowing(_ view: NSTextView) -> [String] {
        guard let manager = view.textLayoutManager, let container = view.textContainer, let storage = view.textStorage else { return ["no layout"] }
        manager.ensureLayout(for: manager.documentRange)
        var out: [String] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  let location = manager.location(manager.documentRange.location, offsetBy: range.location),
                  let fragment = manager.textLayoutFragment(for: location) else { return }
            let start = manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location)
            guard let line = fragment.textLineFragments.first(where: { NSLocationInRange(range.location - start, $0.characterRange) }) else { return }
            let x = fragment.layoutFragmentFrame.minX + line.typographicBounds.minX + line.locationForCharacter(at: range.location - start).x
            let style = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let tail = style.map { $0.tailIndent < 0 ? -$0.tailIndent : 0 } ?? 0
            let right = container.size.width - container.lineFragmentPadding - tail
            guard x < -0.5 || x + attachment.bounds.width > right + 0.5 else { return }
            let text = storage.string as NSString
            let paragraph = text.paragraphRange(for: range)
            let what = text.substring(with: NSRange(location: paragraph.location, length: min(paragraph.length, 20)))
            out.append("\(String(describing: type(of: attachment))) \(Int(x))...\(Int(x + attachment.bounds.width)) of \(Int(right)): \(what.debugDescription)")
        }
        return out
    }

    @Test(arguments: [320, 600, 900] as [CGFloat])
    func noLineReachesPastTheColumn(width: CGFloat) {
        for (name, text) in [("wide", Self.wideThings), ("sample", NoteSourceTests.sample)] {
            let (view, _) = Self.reader(text, width: width)
            NoteRender.write(view, "overflow-\(name)-\(Int(width))")
            let over = Self.overflowing(view)
            #expect(over.isEmpty, "\(name) at \(width): \(over)")
        }
    }

    /// The note's scroll view takes the pointer over the note, so code and a wide formula never got a sideways scroll.
    /// Their own scroll views get the pointer now, never the keyboard, and hand a click on to the note. (A synthetic
    /// wheel event doesn't scroll an `NSScrollView` here, and an overlay scroller only takes clicks once shown, so
    /// both are left to AppKit.)
    @Test func aSidewaysBlockTakesThePointerButNotTheKeyboard() throws {
        let code = "```swift\nlet x = \"a very long line of code that goes on and on and on past the edge of any column at all\"\n```"
        let (view, window) = Self.reader("앞\n\n" + Self.wideMath + "\n\n" + code + "\n\n뒤", width: 600)
        let root = try #require(window.contentView?.superview)
        let sides = view.subviews.compactMap { $0 as? SideScrollView }
        #expect(sides.count == 2)
        for side in sides {
            let hit = try #require(root.hitTest(side.convert(NSPoint(x: side.bounds.midX, y: side.bounds.midY), to: root)))
            #expect(hit === side, "\(type(of: hit))")
            #expect(!hit.acceptsFirstResponder)
            #expect(hit.nextResponder === view)
        }
    }

    @Test func typedMarkupIsEscaped() {
        #expect(ReaderMarkdown.escape("a*b [[c x_y * z") == "a\\*b \\[[c x_y * z")
        #expect(ReaderMarkdown.lines("# 아님\n- 아님\n1. 아님") == "\\# 아님\n\\- 아님\n1\\. 아님")
    }

    @Test func enterInAListMakesTheNextItem() throws {
        let edits = Edits()
        let (view, window) = Self.reader("- [ ] 하나\n- 둘", edits: edits)
        window.makeFirstResponder(view)
        let storage = try #require(view.textStorage)
        let first = (storage.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        view.setSelectedRange(NSRange(location: NSMaxRange(first) - 1, length: 0))
        view.insertNewline(nil)
        view.insertText("셋", replacementRange: view.selectedRange())
        window.makeFirstResponder(nil)
        #expect(edits.all.last?.new == "- [ ] 하나\n- [ ] 셋\n- 둘")
    }

    @Test func boldWrapsTheSelection() throws {
        let edits = Edits()
        let (view, window) = Self.reader("가나 다라", edits: edits)
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 3, length: 2))
        _ = view.shortcut?("b")
        window.makeFirstResponder(nil)
        #expect(edits.all.last?.new == "가나 **다라**")
    }

    @Test func readOnlyBlocksRefuseTyping() throws {
        let edits = Edits()
        let (view, window) = Self.reader("> [!note] 제목\n> 본문", edits: edits)
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.insertText("x", replacementRange: view.selectedRange())
        window.makeFirstResponder(nil)
        #expect(edits.all.isEmpty)
        #expect(!(view.textStorage?.string.contains("x") ?? true))
    }

    @Test func everydayCommandsSwiftMathLacksStillDraw() throws {
        for tex in [#"0, \dots, n-1"#, #"i \bmod n"#, #"a \equiv b \pmod{n}"#, #"a \mod n"#, #"\operatorname{rank} A"#,
                    #"p \implies q"#, #"q \impliedby p"#, #"A \subsetneq B"#, #"a \nmid b"#, #"\therefore x"#, #"\blacksquare"#,
                    #"\square"#, #"\varnothing"#, #"\lvert x \rvert"#, #"\iint f"#, #"\dfrac{1}{2}"#, #"\bigl( x \bigr)"#,
                    #"\boxed{x}"#, #"a \xrightarrow{f} b"#, #"\overset{?}{=}"#, #"a \not= b"#, #"a \lt b"#,
                    #"\left\lvert x \right\rvert"#, #"\left\lVert x \right\rVert"#, #"\lVert x \rVert"#] {
            #expect(NoteMath.picture(tex, syntax: .latex, display: false, size: 16, color: .black, dark: false) != nil, "\(tex)")
        }
        #expect(NoteMath.picture(#"\notacommand{x}"#, syntax: .latex, display: false, size: 16, color: .black, dark: false) == nil)
    }

    @Test func textInMathReadsAsText() throws {
        func width(_ tex: String) throws -> CGFloat {
            try #require(NoteMath.picture(tex, syntax: .latex, display: false, size: 16, color: .black, dark: false), "\(tex)").size.width
        }
        // Math puts room around a minus and a ratio colon; text doesn't.
        #expect(try width(#"\text{a-b}"#) < width(#"\mathrm{a}-\mathrm{b}"#))
        #expect(try width(#"\text{a:b}"#) < width(#"\mathrm{a}:\mathrm{b}"#))
        // Past ASCII SwiftMath dropped the character.
        #expect(try width(#"\text{a–b}"#) > width(#"\text{ab}"#))
        #expect(try width(#"\text{a--b}"#) == width(#"\text{a–b}"#))
        #expect(try width(#"x\text{양이온}"#) > width("x") + 24)
        #expect(try width(#"\text{König–Egerváry: } \alpha'(G) = \beta(G)"#) > 0)
        // SwiftMath dropped `$ % # ~` and read `&` as a table column.
        #expect(try width(#"\text{5% 이내}"#) > width(#"\text{5 이내}"#))
        #expect(try width(#"\text{#3}"#) > width(#"\text{3}"#))
        #expect(try width(#"\text{A&B}"#) == width(#"\text{A\&B}"#))
        #expect(try width(#"\text{a~b}"#) == width(#"\text{a b}"#))
        // Only `\text` kept its spaces.
        #expect(try width(#"\textbf{a b}"#) > width(#"\textbf{ab}"#))
        #expect(try width(#"\textit{강조}"#) > 24)
    }

    @Test func tableColumnsShrinkOnlyAboveWhatCannotWrap() {
        // Math 80 wide in the middle column; the table wants 600 on a 400 page.
        let fitted = ReaderTable.fit([200, 104, 296], floors: [48, 104, 48], page: 400)
        #expect(fitted[1] == 104)
        #expect(fitted.reduce(0, +) <= 400)
        #expect(fitted[0] < 200 && fitted[2] < 296)
        #expect(ReaderTable.fit([100, 100], floors: [48, 48], page: 400) == [100, 100])
        // Floors alone wider than the page: they hold, and the table scrolls sideways instead of cutting formulas.
        #expect(ReaderTable.fit([300, 300], floors: [250, 250], page: 400) == [250, 250])
        #expect(ReaderTable.fit([600, 48, 48], floors: [600, 48, 48], page: 400) == [600, 48, 48])
        // Math in a cell over two columns raises both, so their sum holds it.
        var floors: [CGFloat] = [48, 48, 48]
        ReaderTable.spread(&floors, from: 1, count: 2, to: 224)
        #expect(floors == [48, 112, 112])
        ReaderTable.spread(&floors, from: 0, count: 2, to: 100)
        #expect(floors == [48, 112, 112])
        #expect(ReaderTable.fit([60, 60, 60], floors: floors, page: 400) == [60, 112, 112])
    }

    /// An image in a cell was sized to the note column, so it shrinks to its own column; math can't, so it doesn't.
    /// A table cell is drawn into the table's picture, where a scroll view has nowhere to stand, so a wide formula
    /// there stays a picture and widens its column instead of leaving an empty cell.
    @Test func aWideFormulaInACellStaysAPicture() throws {
        var builder = ReaderBuilder(accent: CourseAccent.presets[0].accent, syntax: .latex, baseURL: nil, dark: false, width: 300, widgets: ReaderWidgets())
        let wide = "$$\\sum_{i=1}^{n} a_i b_i c_i d_i e_i f_i g_i h_i i_i j_i k_i l_i m_i n_i o_i p_i q_i r_i s_i t_i u_i v_i w_i$$"
        let cell = builder.cell(markdown: wide, weight: .regular)
        var attachments: [NSTextAttachment] = []
        cell.enumerateAttribute(.attachment, in: NSRange(location: 0, length: cell.length)) { value, _, _ in
            if let a = value as? NSTextAttachment { attachments.append(a) }
        }
        #expect(attachments.count == 1)
        #expect(attachments.first is MathAttachment, "\(attachments.map { type(of: $0) })")
        #expect((attachments.first?.bounds.width ?? 0) > 300)
    }

    @Test func cellImagesShrinkToTheirColumnButMathDoesNot() throws {
        func piece(_ source: String, width: CGFloat) -> NSAttributedString {
            let a = source.hasPrefix("$") ? MathAttachment() : NSTextAttachment()
            a.bounds = CGRect(x: 0, y: -2, width: width, height: width / 2)
            return NSAttributedString(attachment: a, attributes: [.noteAtom: NoteAtom(source)])
        }
        let text = NSMutableAttributedString(attributedString: piece("![](a.png)", width: 564))
        text.append(piece("$x$", width: 300))
        let out = ReaderTable.shrunk(text, to: 200)
        let image = try #require(out.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        let math = try #require(out.attribute(.attachment, at: 1, effectiveRange: nil) as? NSTextAttachment)
        #expect(image.bounds.width == 200 && image.bounds.height == 100)
        #expect(math.bounds.width == 300)
    }
}
