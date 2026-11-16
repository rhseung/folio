import FolioDomain
import Foundation
import Testing

struct ChatAppliedTests {
    let device = UUID()

    func chat(_ proposals: [ActionProposal]) -> Chat {
        Chat(device: device, at: .now, messages: [ChatMessage(role: .assistant, text: "", at: .now, proposals: proposals)])
    }

    @Test func aProposalAnotherDeviceAppliedReadsAsApplied() {
        let done = UUID(), open = UUID()
        let marked = chat([
            ActionProposal(id: done, command: "exam add", input: .null, failure: "이미 있는 ID"),
            ActionProposal(id: open, command: "exam add", input: .null),
            ActionProposal(command: "exam add", input: .null),
        ]).markingApplied([done])
        let proposals = marked.messages[0].proposals ?? []
        #expect(proposals.map { $0.applied == true } == [true, false, false])
        #expect(proposals[0].failure == nil)
    }

    @Test func nothingAppliedLeavesTheChat() {
        let c = chat([ActionProposal(id: UUID(), command: "exam add", input: .null)])
        #expect(c.markingApplied([]) == c)
        #expect(c.markingApplied([UUID()]) == c)
    }
}
