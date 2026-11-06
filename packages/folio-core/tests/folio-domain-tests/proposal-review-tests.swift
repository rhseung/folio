import FolioDomain
import Foundation
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

    /// The last line's newline doesn't count as a line, but adding one where there was none is a change.
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
        #expect(lines == [.skipped(7), .same("line 8"), .same("line 9"), .removed("line 10"), .added("changed"),
                          .same("line 11"), .same("line 12"), .skipped(8)])
    }

    @Test func aRunBetweenTwoChangesKeepsContextOnBothSides() {
        let old = (1...10).map(String.init)
        var new = old
        new[0] = "x"
        new[9] = "y"
        #expect(TextDiff.fold(TextDiff.full(from: old, to: new), context: 1)
            == [.removed("1"), .added("x"), .same("2"), .skipped(6), .same("9"), .removed("10"), .added("y")])
    }

    /// Hiding one line saves nothing, so it stays.
    @Test func aSingleHiddenLineIsShown() {
        #expect(TextDiff.lines(from: "a\nb\nc\nd", to: "a\nb\nc\nD", context: 2) == [.same("a"), .same("b"), .same("c"), .removed("d"), .added("D")])
        #expect(TextDiff.lines(from: "a\nb\nc\nd\ne", to: "a\nb\nc\nd\nE", context: 2) == [.skipped(2), .same("c"), .same("d"), .removed("e"), .added("E")])
    }

    static let text = Gen.int(in: 0...3).array(of: 0...12).map { $0.map(String.init) }

    @Test func theFullDiffGivesBackBothTexts() async {
        await propertyCheck(input: Self.text, Self.text) { old, new in
            let lines = TextDiff.full(from: old, to: new)
            let before = lines.compactMap { line -> String? in
                switch line { case .same(let s), .removed(let s): s; default: nil }
            }
            let after = lines.compactMap { line -> String? in
                switch line { case .same(let s), .added(let s): s; default: nil }
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
                #expect(!zip(folded, folded.dropFirst()).contains { a, b in
                    if case .skipped = a, case .skipped = b { true } else { false }
                })
            }
        }
    }
}

struct SupersededProposalTests {
    let now = Date(timeIntervalSince1970: 0)
    // As FolioActions declares them; `note edit` and `exam add` only add, so they have none.
    let targets: [String: ProposalTarget] = [
        "note write": ProposalTarget(arguments: ["course", "note"], effect: .replaces(covers: ["note edit"])),
        "note link": ProposalTarget(arguments: ["course", "note"], effect: .sets),
        "exam set": ProposalTarget(arguments: ["course", "exam"], effect: .sets),
    ]

    func write(_ note: String, course: String = "c") -> ActionProposal {
        ActionProposal(command: "note write", input: .object(["course": .string(course), "note": .string(note), "text": .string("본문")]))
    }

    func edit(_ fields: [String: JSONValue]) -> ActionProposal {
        ActionProposal(command: "note edit", input: .object(["course": .string("c"), "note": .string("Notes/a.md")].merging(fields) { a, _ in a }))
    }

    func examSet(_ fields: [String: JSONValue], exam: String = "e") -> ActionProposal {
        ActionProposal(command: "exam set", input: .object(["course": .string("c"), "exam": .string(exam)].merging(fields) { a, _ in a }))
    }

    let replacement: JSONValue = .array([.object(["old": .string("teh"), "new": .string("the")])])

    /// An append and a later typo fix are two changes; neither makes the other pointless.
    @Test func editsOnlyAddSoTheyNeverSupersede() {
        #expect(chat([[edit(["append": .string("질문")])], [edit(["replacements": replacement])]]).supersededProposals(targets: targets).isEmpty)
        #expect(chat([[edit(["append": .string("질문")])], [edit(["append": .string("질문")])]]).supersededProposals(targets: targets).isEmpty)
    }

    @Test func aRewriteSupersedesAnEarlierEditOfTheSameNote() {
        let c = chat([[edit(["append": .string("질문")]), write("Notes/b.md")], [write("Notes/a.md")]])
        #expect(c.supersededProposals(targets: targets) == [ProposalRef(message: c.messages[1].id, index: 0)])
    }

    /// Setting the start and then the place of one exam are two changes: the later leaves the start as it is.
    @Test func aSetSupersedesOnlyWhenItSetsEveryFieldTheEarlierSet() {
        let start: JSONValue = .string("2026-11-10T09:00:00Z")
        #expect(chat([[examSet(["start": start])], [examSet(["location": .string("B101")])]]).supersededProposals(targets: targets).isEmpty)
        let c = chat([[examSet(["start": start])], [examSet(["start": .string("2026-11-11T09:00:00Z"), "location": .string("B101")])]])
        #expect(c.supersededProposals(targets: targets) == [ProposalRef(message: c.messages[1].id, index: 0)])
        #expect(chat([[examSet(["start": start])], [examSet(["start": start], exam: "f")]]).supersededProposals(targets: targets).isEmpty)
    }

    /// `null` clears a field, so it sets it; a field left out stays as it is.
    @Test func clearingAFieldCountsAsSettingIt() {
        let c = chat([[examSet(["start": .string("2026-11-10T09:00:00Z")])], [examSet(["start": .null])]])
        #expect(c.supersededProposals(targets: targets) == [ProposalRef(message: c.messages[1].id, index: 0)])
        #expect(chat([[examSet(["start": .null])], [examSet([:])]]).supersededProposals(targets: targets).isEmpty)
    }

    func chat(_ answers: [[ActionProposal]]) -> Chat {
        Chat(device: UUID(), at: now, messages: answers.flatMap { proposals in
            [ChatMessage(role: .user, text: "q", at: now), ChatMessage(role: .assistant, text: "a", at: now, proposals: proposals)]
        })
    }

    @Test func aLaterProposalForTheSameNoteSupersedesTheEarlierOne() {
        let c = chat([[write("Notes/a.md"), write("Notes/b.md")], [write("Notes/a.md")]])
        #expect(c.supersededProposals(targets: targets) == [ProposalRef(message: c.messages[1].id, index: 0)])
    }

    /// A link isn't a rewrite, and a later edit adds: neither stands in for an earlier rewrite.
    @Test func anotherNoteCourseOrCommandIsNotTheSameChange() {
        var link = write("Notes/a.md")
        link.command = "note link"
        let c = chat([[write("Notes/a.md")], [write("Notes/b.md"), write("Notes/a.md", course: "d"), link, edit(["append": .string("x")])]])
        #expect(c.supersededProposals(targets: targets).isEmpty)
    }

    /// Two changes in one answer are both offered; the older answer's line is the one replaced.
    @Test func proposalsOfOneAnswerDontSupersedeEachOther() {
        let c = chat([[write("Notes/a.md"), write("Notes/a.md")]])
        #expect(c.supersededProposals(targets: targets).isEmpty)
    }

    @Test func anAppliedProposalStaysAppliedButStillSupersedes() {
        var applied = write("Notes/a.md")
        applied.applied = true
        #expect(chat([[applied], [write("Notes/a.md")]]).supersededProposals(targets: targets).isEmpty)
        let c = chat([[write("Notes/a.md")], [applied]])
        #expect(c.supersededProposals(targets: targets) == [ProposalRef(message: c.messages[1].id, index: 0)])
    }

    @Test func aCommandWithoutTargetsIsNeverSuperseded() {
        let add = ActionProposal(command: "session add", input: .object(["course": .string("c")]))
        #expect(chat([[add], [add]]).supersededProposals(targets: targets).isEmpty)
        #expect(chat([[add], [add]]).supersededProposals(targets: ["session add": ProposalTarget(arguments: [], effect: .replaces(covers: []))]).isEmpty)
        #expect(add.target(["course", "missing"]) == .object(["course": .string("c"), "missing": .null]))
    }
}
