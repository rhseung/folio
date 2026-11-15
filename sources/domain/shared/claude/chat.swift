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

extension Chat {
    // 적용하지 않았고 뒤 제안에 대체되지 않은 제안이다. 다른 기기가 적용한 제안을 빼려면 먼저
    // `markingApplied`를 거친다.
    public func pending(course: UUID, targets: [String: ProposalTarget]) -> [Proposal] {
        let superseded = supersededProposals(targets: targets)
        return messages.flatMap { m in
            (m.proposals ?? []).enumerated().compactMap { i, p -> Proposal? in
                guard p.applied != true, !superseded.contains(ProposalRef(message: m.id, index: i)) else { return nil }
                let source = ChatProposal(course: course, chat: id, chatTitle: title, message: m.id, index: i, proposal: p)
                return Proposal(kind: .claude, source: .claude(source), action: p)
            }
        }
    }
}
