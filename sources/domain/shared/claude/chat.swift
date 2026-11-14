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
