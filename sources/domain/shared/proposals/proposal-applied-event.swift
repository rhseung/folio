import Foundation

public struct ProposalAppliedEvent: LogEvent, Equatable {
    public static let type = "proposal_applied"
    public var proposal: UUID
    public var command: String

    public init(proposal: UUID, command: String) {
        self.proposal = proposal
        self.command = command
    }
}
