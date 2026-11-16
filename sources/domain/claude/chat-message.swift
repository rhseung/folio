import Foundation

public struct ChatMessage: Codable, Sendable, Equatable, Identifiable {
    public enum Role: String, Codable, Sendable { case user, assistant }

    public var id: UUID
    public var role: Role
    public var text: String
    public var at: Date
    public var context: [String]
    public var proposals: [ActionProposal]?

    public init(id: UUID = UUID(), role: Role, text: String, at: Date, context: [String] = [], proposals: [ActionProposal]? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.at = at
        self.context = context
        self.proposals = proposals
    }
}
