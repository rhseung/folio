import FolioCore
import PropertyBased
import Testing

struct TextDiffTests {
    @Test func aChangedLineReadsAsRemovedThenAdded() {
        #expect(TextDiff.lines(from: "a\nb\nc\n", to: "a\nB\nc\n") == [.same("a"), .removed("b"), .added("B"), .same("c")])
    }

    @Test func nothingChangedIsEmpty() {
        #expect(TextDiff.lines(from: "a\nb\n", to: "a\nb\n").isEmpty)
        #expect(TextDiff.lines(from: "", to: "").isEmpty)
    }

    @Test func aNewOrEmptiedNoteIsAllAddedOrRemoved() {
        #expect(TextDiff.lines(from: "", to: "# 제목\n본문\n") == [.added("# 제목"), .added("본문")])
        #expect(TextDiff.lines(from: "x\ny", to: "") == [.removed("x"), .removed("y")])
    }

    @Test func theFinalNewline() {
        #expect(TextDiff.split("a\nb\n") == ["a", "b"])
        #expect(TextDiff.split("a\nb") == ["a", "b"])
        #expect(TextDiff.split("a\n\n") == ["a", ""])
        #expect(TextDiff.lines(from: "a\nb", to: "a\nb\n").isEmpty)
    }

    @Test func longUnchangedRunsFoldWithContextKept() {
        let old = (1...20).map { "line \($0)" }
        var new = old
        new[9] = "changed"
        let lines = TextDiff.fold(TextDiff.full(from: old, to: new), context: 2)
        #expect(
            lines == [
                .skipped(7), .same("line 8"), .same("line 9"), .removed("line 10"), .added("changed"),
                .same("line 11"), .same("line 12"), .skipped(8),
            ])
    }

    @Test func aRunBetweenTwoChangesKeepsContextOnBothSides() {
        let old = (1...10).map(String.init)
        var new = old
        new[0] = "x"
        new[9] = "y"
        #expect(
            TextDiff.fold(TextDiff.full(from: old, to: new), context: 1)
                == [.removed("1"), .added("x"), .same("2"), .skipped(6), .same("9"), .removed("10"), .added("y")])
    }

    @Test func aSingleHiddenLineIsShown() {
        #expect(
            TextDiff.lines(from: "a\nb\nc\nd", to: "a\nb\nc\nD", context: 2) == [
                .same("a"), .same("b"), .same("c"), .removed("d"), .added("D"),
            ])
        #expect(
            TextDiff.lines(from: "a\nb\nc\nd\ne", to: "a\nb\nc\nd\nE", context: 2) == [
                .skipped(2), .same("c"), .same("d"), .removed("e"), .added("E"),
            ])
    }

    static let text = Gen.int(in: 0...3).array(of: 0...12).map { $0.map(String.init) }

    @Test func theFullDiffGivesBackBothTexts() async {
        await propertyCheck(input: Self.text, Self.text) { old, new in
            let lines = TextDiff.full(from: old, to: new)
            let before = lines.compactMap { line -> String? in
                switch line {
                case .same(let s), .removed(let s): s
                default: nil
                }
            }
            let after = lines.compactMap { line -> String? in
                switch line {
                case .same(let s), .added(let s): s
                default: nil
                }
            }
            #expect(before == old)
            #expect(after == new)
        }
    }

    @Test func foldingKeepsEveryChangeAndCountsEveryLine() async {
        await propertyCheck(input: Self.text, Self.text, Gen.int(in: 0...3)) { old, new, context in
            let full = TextDiff.full(from: old, to: new)
            let folded = TextDiff.fold(full, context: context)
            func changes(_ lines: [TextDiff.Line]) -> [TextDiff.Line] {
                lines.filter { if case .same = $0 { false } else if case .skipped = $0 { false } else { true } }
            }
            #expect(changes(folded) == changes(full))
            if changes(full).isEmpty {
                #expect(folded.isEmpty)
            } else {
                let counted = folded.reduce(0) { n, line in if case .skipped(let k) = line { n + k } else { n + 1 } }
                #expect(counted == full.count)
                #expect(
                    !zip(folded, folded.dropFirst()).contains { a, b in
                        if case .skipped = a, case .skipped = b { true } else { false }
                    })
            }
        }
    }
}
