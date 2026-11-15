import Foundation

// 대화 파일 안의 제안 하나를 가리킨다. 대화는 과목마다 `.folio/chats/`에 있다.
public struct ChatProposal: Hashable, Sendable {
    public var course: UUID
    public var chat: UUID
    public var chatTitle: String
    public var message: UUID
    public var index: Int
    public var proposal: ActionProposal

    public init(course: UUID, chat: UUID, chatTitle: String, message: UUID, index: Int, proposal: ActionProposal) {
        self.course = course
        self.chat = chat
        self.chatTitle = chatTitle
        self.message = message
        self.index = index
        self.proposal = proposal
    }

    public var ref: ProposalRef { ProposalRef(message: message, index: index) }
}
