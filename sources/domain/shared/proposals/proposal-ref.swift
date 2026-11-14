import Foundation

public struct ProposalRef: Hashable, Sendable {
    public var message: UUID
    public var index: Int

    public init(message: UUID, index: Int) {
        self.message = message
        self.index = index
    }
}
