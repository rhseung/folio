import Foundation
import Testing

@testable import FolioMarkdown

struct NoteBlockCardTests {
    let text = "---\ntitle: 매칭\n---\n# 매칭\n\n> [!definition] 매칭\n> 공통 끝점이 없는 변의 집합이다.\n> $|M|$은 변의 수다.\n\n> [!note] 참고\n> 안내문\n"

    @Test func aDefinitionBecomesFrontAndBack() throws {
        let card = try #require(NoteBlockCard.at(line: 3, in: text))
        #expect(card.front == "매칭" && card.type == "definition")
        #expect(card.back == "공통 끝점이 없는 변의 집합이다.\n$|M|$은 변의 수다.")
        #expect(card.blockID == nil && card.lines == 3...5)
    }

    @Test func notesAndOtherLinesAreNotCards() {
        #expect(NoteBlockCard.at(line: 7, in: text) == nil)
        #expect(NoteBlockCard.at(line: 4, in: text) == nil)
    }

    @Test func taggingTheLastLineLetsTheCardFindItsBlockAgain() throws {
        let card = try #require(NoteBlockCard.at(line: 3, in: text))
        let tag = try #require(card.tagged(text, id: "m1"))
        #expect(tag.line == 8 && tag.new == "> $|M|$은 변의 수다. ^m1")
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[tag.line - 1] == tag.old)
        lines[tag.line - 1] = tag.new
        let tagged = lines.joined(separator: "\n")
        let again = try #require(NoteBlockCard.at(line: 3, in: tagged))
        #expect(again.blockID == "m1" && again.back == card.back)
        #expect(again.tagged(tagged, id: "x") == nil)
        #expect(NoteBlockCard.source(of: "m1", in: tagged)?.hasPrefix("> [!definition] 매칭") == true)
        #expect(NoteBlockCard.source(of: "gone", in: tagged) == nil)
        #expect(NoteBlockCard.find("m1", in: tagged)?.front == "매칭")
    }

    @Test func anUntitledTheoremIsNamedByItsKind() throws {
        let card = try #require(NoteBlockCard.at(line: 1, in: "> [!theorem]\n> 홀의 정리"))
        #expect(card.front == "Theorem" && card.back == "홀의 정리")
    }
}
