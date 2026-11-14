import Foundation
import Testing

@testable import FolioMarkdown

struct LinkCompletionTests {
    func query(_ s: String) -> CompletionQuery? {
        let m = Marked(s)
        return Completion.query(in: m.text, caret: m.selection.location, catalog: CompletionCatalog())
    }

    func link(_ s: String) -> LinkQuery? {
        if case .link(let l) = query(s)?.kind { l } else { nil }
    }

    @Test func readsThePartBeingTyped() {
        #expect(link("[[그래|]]") == LinkQuery(part: .target))
        #expect(query("[[그래|]]")?.text == "그래")
        #expect(link("앞 ![[|]]") == LinkQuery(part: .target, embed: true))
        #expect(link("[[매칭#정|]]") == LinkQuery(part: .heading, target: "매칭"))
        #expect(query("[[매칭#정|]]")?.text == "정")
        #expect(link("[[note:ABC#^x|]]") == LinkQuery(part: .block, target: "note:ABC"))
        #expect(link("[[material:ABC#page=1|]]") == LinkQuery(part: .page, target: "material:ABC"))
        #expect(query("[[material:ABC#page=1|]]")?.text == "1")
        #expect(link("[[매칭|#제목|보이는 이름]]") == LinkQuery(part: .target, alias: "보이는 이름"))
    }

    @Test func offersNothingWhereNoLinkIsBeingWritten() {
        #expect(query("[[매칭|이«»]]") == nil)
        #expect(query("[[매칭]] 뒤|") == nil)
        #expect(query("[[#제목|]]") == nil)
        #expect(query("[[material:A#page=x|]]") == nil)
        #expect(query("`[[|`") == nil)
        #expect(query("$[[|$") == nil)
        #expect(link("[[a /b|]]") == LinkQuery(part: .target))
    }

    @Test func aCandidateReplacesTheWholeLink() {
        let m = Marked("앞 [[그래#|프]] 뒤")
        let q = Completion.query(in: m.text, caret: m.selection.location, catalog: CompletionCatalog())!
        #expect(m.text.substring(with: q.range) == "[[그래#프]]")
        let link = "[[note:X|그래프]]"
        let item = CompletionItem(id: "n", title: "그래프", body: link, caret: link.utf16.count)
        #expect(Marked.show(m.text, Completion.edit(accepting: item, for: q, in: m.text)) == "앞 [[note:X|그래프]]| 뒤")
        let open = Marked("[[그래| 뒤")
        let q2 = Completion.query(in: open.text, caret: open.selection.location, catalog: CompletionCatalog())!
        #expect(open.text.substring(with: q2.range) == "[[그래")
    }

    @Test func typingKeepsTheSameQuery() {
        let a = query("[[그|]]")!, b = query("[[그래|]]")!
        #expect(b.continues(a))
        #expect(!query("[[그래#|]]")!.continues(b))
        #expect(query("[[그래#ab|]]")!.continues(query("[[그래#a|]]")!))
    }

    @Test func writesLinksByID() {
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF")!
        #expect(WikiLink.written("note", id, alias: "매칭 [1] | 정리") == "[[note:6F9619FF-8B86-D011-B42D-00CF4FC964FF|매칭 1 정리]]")
        #expect(
            WikiLink.written("material", id, fragment: "page=3", alias: "a.pdf", embed: true)
                == "![[material:6F9619FF-8B86-D011-B42D-00CF4FC964FF#page=3|a.pdf]]")
        let back = WikiLink.all(in: WikiLink.written("note", id, fragment: "^blk", alias: "제목"))
        #expect(back.first?.noteID == id && back.first?.blockID == "blk" && back.first?.alias == "제목")
        #expect(!WikiLink.linkable(heading: "a | b") && WikiLink.linkable(heading: "정의와 예"))
    }

    @Test func listsHeadingsAndBlocks() {
        let note = ParsedNote(
            """
            ---
            tags: [a]
            ---
            # 매칭

            증가 경로가 없으면 최대다. ^max

            - 첫 항목
              이어진 줄
              - 아래 항목
            - [ ] 할 일

            > [!definition] 매칭
            > 이웃하지 않는 변

            $$
            x
            $$

            ## 예
            """)
        #expect(note.headings.map(\.text) == ["매칭", "예"])
        #expect(note.headings.map(\.level) == [1, 2])
        let blocks = note.linkableBlocks
        #expect(blocks.map(\.excerpt) == ["증가 경로가 없으면 최대다.", "첫 항목", "아래 항목", "할 일", "매칭"])
        #expect(blocks.map(\.id) == ["max", nil, nil, nil, nil])
        #expect(blocks.map(\.line) == [3, 6, 7, 8, 11])
    }

    @Test func aNewBlockIDGoesAtTheEndOfItsLine() throws {
        let text = "---\nk: v\n---\n- 첫 항목\n  이어진 줄  \n  - 아래\n"
        let block = try #require(ParsedNote(text).linkableBlocks.first)
        let edit = try #require(ParsedNote.blockTag(in: text, line: block.line, id: "abc123"))
        let tagged = edit.applied(to: text as NSString)
        #expect(tagged == "---\nk: v\n---\n- 첫 항목\n  이어진 줄 ^abc123  \n  - 아래\n")
        #expect(ParsedNote(tagged).section(heading: nil, block: "abc123") == "- 첫 항목\n  이어진 줄 ^abc123  \n  - 아래")
    }

    @Test func newBlockIDsAvoidTheTakenOnes() {
        var generator = SeededGenerator(seed: 7)
        let first = BlockID.make(avoiding: [], using: &generator)
        var again = SeededGenerator(seed: 7)
        #expect(BlockID.make(avoiding: [first], using: &again) != first)
        #expect(first.wholeMatch(of: /[a-z0-9]{6}/) != nil)
    }
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
