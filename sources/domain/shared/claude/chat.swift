import Foundation

public struct Chat: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var title: String
    public var messages: [ChatMessage]

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, title: String = "새 대화", messages: [ChatMessage] = []) {
        self.id = id
        createdAt = date
        updatedAt = date
        updatedBy = device
        self.title = title
        self.messages = messages
    }
}

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
