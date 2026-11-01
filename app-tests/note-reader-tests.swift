import AppKit
import FolioDomain
import FolioMarkdown
import Foundation
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
        #expect(storage.string.contains("이건 다이어그램이 아니다"))
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
}
