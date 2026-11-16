import FolioCore
import Foundation

public struct PlannedMove: Codable, Sendable, Hashable {
    public var from: String
    public var to: String
    public var review: ReviewReason?
    public var exam: String?
    public var kind: MaterialKind?

    public init(from: String, to: String, review: ReviewReason? = nil, exam: String? = nil, kind: MaterialKind? = nil) {
        self.from = from
        self.to = to
        self.review = review
        self.exam = exam
        self.kind = kind
    }
}

extension PlannedMove {
    public var proposal: Proposal {
        let input = (try? JSONEncoder().encode(self)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
        return Proposal(
            kind: .cleanupMove, source: .cleanup(self), action: ActionProposal(command: "cleanup apply", input: ["moves": [input]]),
            flag: review.map(ProposalFlag.review))
    }
}
