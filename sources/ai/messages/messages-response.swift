import FolioDomain
import Foundation

public struct MessagesResponse: Codable, Sendable, Equatable {
    public var id: String
    public var model: String
    public var content: [ContentBlock]
    public var stop_reason: String?
    public var usage: Usage
    public var proposals: [ActionProposal]?

    public init(id: String, model: String, content: [ContentBlock], stop_reason: String?, usage: Usage, proposals: [ActionProposal]? = nil)
    {
        self.id = id
        self.model = model
        self.content = content
        self.stop_reason = stop_reason
        self.usage = usage
        self.proposals = proposals
    }

    public var text: String {
        content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }.joined()
    }
}
