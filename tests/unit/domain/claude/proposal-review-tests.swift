import FolioCore
import FolioDomain
import Foundation
import Testing

struct SupersededProposalTests {
    let now = Date(timeIntervalSince1970: 0)
    let targets: [String: ProposalTarget] = [
        "note write": ProposalTarget(arguments: ["course", "note"], effect: .replaces(covers: ["note edit"])),
        "note link": ProposalTarget(arguments: ["course", "note"], effect: .sets),
        "exam set": ProposalTarget(arguments: ["course", "exam"], effect: .sets),
    ]

    func write(_ note: String, course: String = "c") -> ActionProposal {
        ActionProposal(command: "note write", input: .object(["course": .string(course), "note": .string(note), "text": .string("본문")]))
    }

    func edit(_ fields: [String: JSONValue]) -> ActionProposal {
        ActionProposal(
            command: "note edit", input: .object(["course": .string("c"), "note": .string("Notes/a.md")].merging(fields) { a, _ in a }))
    }

    func examSet(_ fields: [String: JSONValue], exam: String = "e") -> ActionProposal {
        ActionProposal(command: "exam set", input: .object(["course": .string("c"), "exam": .string(exam)].merging(fields) { a, _ in a }))
    }

    let replacement: JSONValue = .array([.object(["old": .string("teh"), "new": .string("the")])])

    @Test func editsOnlyAddSoTheyNeverSupersede() {
        #expect(
            chat([[edit(["append": .string("질문")])], [edit(["replacements": replacement])]]).supersededProposals(targets: targets).isEmpty)
        #expect(chat([[edit(["append": .string("질문")])], [edit(["append": .string("질문")])]]).supersededProposals(targets: targets).isEmpty)
    }

    @Test func aRewriteSupersedesAnEarlierEditOfTheSameNote() {
        let c = chat([[edit(["append": .string("질문")]), write("Notes/b.md")], [write("Notes/a.md")]])
        #expect(c.supersededProposals(targets: targets) == [ProposalRef(message: c.messages[1].id, index: 0)])
    }

    @Test func aSetSupersedesOnlyWhenItSetsEveryFieldTheEarlierSet() {
        let start: JSONValue = .string("2026-11-10T09:00:00Z")
        #expect(
            chat([[examSet(["start": start])], [examSet(["location": .string("B101")])]]).supersededProposals(targets: targets).isEmpty)
        let c = chat([[examSet(["start": start])], [examSet(["start": .string("2026-11-11T09:00:00Z"), "location": .string("B101")])]])
        #expect(c.supersededProposals(targets: targets) == [ProposalRef(message: c.messages[1].id, index: 0)])
        #expect(chat([[examSet(["start": start])], [examSet(["start": start], exam: "f")]]).supersededProposals(targets: targets).isEmpty)
    }

    @Test func clearingAFieldCountsAsSettingIt() {
        let c = chat([[examSet(["start": .string("2026-11-10T09:00:00Z")])], [examSet(["start": .null])]])
        #expect(c.supersededProposals(targets: targets) == [ProposalRef(message: c.messages[1].id, index: 0)])
        #expect(chat([[examSet(["start": .null])], [examSet([:])]]).supersededProposals(targets: targets).isEmpty)
    }

    func chat(_ answers: [[ActionProposal]]) -> Chat {
        Chat(
            device: UUID(), at: now,
            messages: answers.flatMap { proposals in
                [ChatMessage(role: .user, text: "q", at: now), ChatMessage(role: .assistant, text: "a", at: now, proposals: proposals)]
            })
    }

    @Test func aLaterProposalForTheSameNoteSupersedesTheEarlierOne() {
        let c = chat([[write("Notes/a.md"), write("Notes/b.md")], [write("Notes/a.md")]])
        #expect(c.supersededProposals(targets: targets) == [ProposalRef(message: c.messages[1].id, index: 0)])
    }

    @Test func anotherNoteCourseOrCommandIsNotTheSameChange() {
        var link = write("Notes/a.md")
        link.command = "note link"
        let c = chat([
            [write("Notes/a.md")], [write("Notes/b.md"), write("Notes/a.md", course: "d"), link, edit(["append": .string("x")])],
        ])
        #expect(c.supersededProposals(targets: targets).isEmpty)
    }

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
        #expect(
            chat([[add], [add]]).supersededProposals(targets: ["session add": ProposalTarget(arguments: [], effect: .replaces(covers: []))])
                .isEmpty)
        #expect(add.target(["course", "missing"]) == .object(["course": .string("c"), "missing": .null]))
    }
}

struct ProposalWaitingTests {
    func message(_ proposals: [ActionProposal]) -> ChatMessage {
        ChatMessage(role: .assistant, text: "", at: Date(timeIntervalSince1970: 0), proposals: proposals)
    }

    func proposal(after: [Int]? = nil, applied: Bool? = nil) -> ActionProposal {
        ActionProposal(command: "unit pages add", input: .object([:]), applied: applied, after: after)
    }

    @Test func standsAloneWithoutEarlierOnes() {
        let m = message([proposal(), proposal()])
        #expect(m.waiting(1) { _ in false } == nil)
        #expect(m.waiting(5) { _ in false } == nil)
    }

    @Test func waitsUntilTheEarlierOnesAreApplied() {
        #expect(message([proposal(), proposal(), proposal(after: [0, 1])]).waiting(2) { _ in false } == .earlier([0, 1]))
        #expect(message([proposal(applied: true), proposal(), proposal(after: [0, 1])]).waiting(2) { _ in false } == .earlier([1]))
        #expect(message([proposal(applied: true), proposal(after: [0])]).waiting(1) { _ in true } == nil)
        #expect(message([proposal(after: [0, 1])]).waiting(0) { _ in false } == nil)
    }

    @Test func anEarlierOneThatCantBeAppliedBlocksIt() {
        #expect(message([proposal(), proposal(after: [0])]).waiting(1) { $0 == 0 } == .blocked([0]))
    }

    @Test func aChainWaitsThroughOneThatIsItselfWaiting() {
        let chain = message([proposal(), proposal(after: [0]), proposal(after: [1])])
        #expect(chain.waiting(2) { $0 == 1 } == .earlier([1]))
        #expect(chain.waiting(2) { $0 <= 1 } == .blocked([1]))
    }

    @Test func onlyCommandsThatWriteInsideTheFolderStage() {
        for command in ["unit add", "note edit", "exam set", "assignment add"] { #expect(ActionProposal.stages(command), "\(command)") }
        for command in ["backup create", "cleanup apply", "import notion", "recording trim", ""] {
            #expect(!ActionProposal.stages(command), "\(command)")
        }
    }

    @Test func theEarlierPlacesSurviveTheChatFile() throws {
        let p = proposal(after: [0, 2])
        #expect(ActionProposal(text: p.text)?.after == [0, 2])
        #expect(ActionProposal(text: proposal().text)?.after == nil)
    }
}
