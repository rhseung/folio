import Foundation
import Testing

@testable import FolioMarkdown

struct NoteAnchorTests {
    let body = """
        # 매칭

        소개

        ## 정의

        짝짓기는
        간선 집합이다. ^def

        - 하나
            - 안쪽 ^inner
        - 둘 ^two

        > [!theorem] 베르주
        > 증강 경로가 없다. ^berge
        """

    /// The line at a location, as the editor would show it with the caret there.
    func line(at location: Int?, in text: String) -> String? {
        guard let location else { return nil }
        let ns = text as NSString
        return ns.substring(with: ns.lineRange(for: NSRange(location: location, length: 0))).trimmingCharacters(in: .newlines)
    }

    @Test func aHeadingLandsOnItsLine() {
        let note = ParsedNote(body)
        #expect(note.line(heading: "정의", block: nil) == 5)
        #expect(note.line(heading: "매칭", block: nil) == 1)
        // Matched as the preview matches it: by text ignoring case, or by its slug.
        #expect(line(at: ParsedNote.location(in: body, heading: " 정의 ", block: nil), in: body) == "## 정의")
        #expect(ParsedNote.location(in: body, heading: "없는 제목", block: nil) == nil)
    }

    @Test func aBlockLandsOnTheFirstLineOfWhatItNames() {
        // A paragraph's ID sits on its last line; the caret goes to where the paragraph starts.
        #expect(line(at: ParsedNote.location(in: body, heading: nil, block: "def"), in: body) == "짝짓기는")
        #expect(line(at: ParsedNote.location(in: body, heading: nil, block: "inner"), in: body) == "    - 안쪽 ^inner")
        #expect(line(at: ParsedNote.location(in: body, heading: nil, block: "two"), in: body) == "- 둘 ^two")
        #expect(line(at: ParsedNote.location(in: body, heading: nil, block: "berge"), in: body) == "> [!theorem] 베르주")
        #expect(ParsedNote.location(in: body, heading: nil, block: "nope") == nil)
    }

    @Test func noAnchorIsNoPlace() {
        #expect(ParsedNote.location(in: body, heading: nil, block: nil) == nil)
    }

    @Test func locationsCountUTF16AndSkipTheFrontmatter() {
        // Hangul and an emoji before the heading: a location in characters would land short of it.
        let text = "---\nid: x\n---\n# 😀 머리\n\n본문\n\n## 끝"
        let location = ParsedNote.location(in: text, heading: "끝", block: nil)
        #expect(location == (text as NSString).range(of: "## 끝").location)
    }
}
