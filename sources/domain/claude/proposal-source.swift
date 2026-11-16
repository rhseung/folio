import Foundation

public enum ProposalSource: Hashable, Sendable {
    case lms(LMSProposal)
    case claude(ChatProposal)
    case cleanup(PlannedMove)
}
