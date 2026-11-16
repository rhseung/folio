import Foundation
import PropertyBased
import Testing

@testable import FolioMarkdown

struct CompletionCaseTests {
    func catalog(tex: Bool) -> CompletionCatalog { CompletionCatalog(tex: tex) }

    func query(_ s: String, tex: Bool = true) throws -> CompletionQuery {
        let m = Marked(s)
        return try #require(Completion.query(in: m.text, caret: m.selection.location, catalog: catalog(tex: tex)))
    }

    func items(_ s: String, tex: Bool = true) throws -> [CompletionItem] {
        Completion.items(for: try query(s, tex: tex), catalog: catalog(tex: tex))
    }

    func tab(_ s: String, tex: Bool = true) throws -> String {
        let m = Marked(s)
        let first = try #require(try items(s, tex: tex).first)
        return Marked.show(m.text, Completion.edit(accepting: first, for: try query(s, tex: tex), in: m.text))
    }

    @Test func typedCaseWinsTheTopButBothCasesStay() throws {
        for typed in ["Delta", "delta", "DELTA"] {
            let titles = try items("$\\\(typed)|$").map(\.title)
            #expect(Array(titles.prefix(2)).sorted() == ["\\Delta", "\\delta"])
        }
        #expect(try tab("$\\Delta|$") == "$\\Delta|$")
        #expect(try tab("$\\delta|$") == "$\\delta|$")
        // 대소문자까지 같은 후보가 없으면 목록 순서를 따른다.
        #expect(try tab("$\\DELTA|$") == "$\\delta|$")
    }

    @Test func oneLetterPutsItsOwnCaseFirst() throws {
        let upper = try items("$\\D|$").map(\.title)
        let lower = try items("$\\d|$").map(\.title)
        #expect(Set(upper) == Set(lower) && upper.contains("\\Delta") && upper.contains("\\delta"))
        let split = upper.firstIndex { !$0.hasPrefix("\\D") } ?? upper.endIndex
        #expect(split > 0 && upper[split...].allSatisfy { $0.hasPrefix("\\d") })
        #expect(lower.first?.hasPrefix("\\d") == true && lower.contains { $0.hasPrefix("\\D") })
    }

    @Test func asciiMathWordsFollowTheSameRule() throws {
        let found = try items("$x + Delta|$", tex: false)
        #expect(try query("$x + Delta|$", tex: false).kind == .asciiMath && Set(found.prefix(2).map(\.title)) == ["Delta", "delta"])
        #expect(try tab("$x + Delta|$", tex: false) == "$x + Delta|$")
        #expect(try tab("$x + delta|$", tex: false) == "$x + delta|$")
        #expect(try tab("$x \\Delta|$", tex: false) == "$x Delta|$")
    }

    @Test func caseOnlyBreaksTiesWithinARank() {
        let list = ["note", "Notes", "NOTE", "keynote"].map { CompletionItem(id: $0, title: $0, body: $0) }
        #expect(Completion.filter(list, "NOTE").map(\.title) == ["NOTE", "note", "Notes", "keynote"])
        #expect(Completion.filter(list, "Note").map(\.title) == ["note", "NOTE", "Notes", "keynote"])
        #expect(Completion.filter(list, "No").map(\.title) == ["Notes", "note", "NOTE", "keynote"])
        let keyed = [
            CompletionItem(id: "a", title: "표", keywords: ["table"], body: ""),
            CompletionItem(id: "b", title: "목록", keywords: ["Table"], body: ""),
        ]
        #expect(Completion.filter(keyed, "Tab").map(\.id) == ["b", "a"])
    }

    @Test func caseNeverChangesWhatMatches() async {
        let names = TeXCommands.all.map(\.name)
        await propertyCheck(input: Gen.int(in: 0...(names.count - 1)), Gen.int(in: 1...12), Gen.bool.array(of: 12)) { at, length, flips in
            let typed = String(
                zip(names[at].prefix(length), flips).map { c, up in up ? Character(c.uppercased()) : Character(c.lowercased()) })
            let found = Completion.filter(TeXCommands.all.map(\.item), typed, prefixOnly: true)
            let folded = Completion.filter(TeXCommands.all.map(\.item), typed.lowercased(), prefixOnly: true)
            #expect(Set(found.map(\.id)) == Set(folded.map(\.id)))
            if found.contains(where: { $0.title == "\\" + typed }) { #expect(found.first?.title == "\\" + typed) }
        }
    }
}
