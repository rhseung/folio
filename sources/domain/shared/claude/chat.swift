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

    // 다른 기기가 먼저 적용한 제안은 이 기기의 대화 파일에 적용 표시가 없다. 과목 문서에 남은 제안 ID로 적용된 것으로
    // 읽는다. 그러지 않으면 새 항목을 더하는 제안은 미리 실행에서 ID가 겹쳐 거절된 것으로 보인다.
    public func markingApplied(_ applied: Set<UUID>) -> Chat {
        guard !applied.isEmpty else { return self }
        var chat = self
        for m in chat.messages.indices {
            for i in (chat.messages[m].proposals ?? []).indices {
                guard let id = chat.messages[m].proposals?[i].id, applied.contains(id) else { continue }
                chat.messages[m].proposals?[i].applied = true
                chat.messages[m].proposals?[i].failure = nil
            }
        }
        return chat
    }
}
