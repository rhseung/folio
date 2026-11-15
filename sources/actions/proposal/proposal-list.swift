import FolioDomain
import FolioStorage
import Foundation

@Query(
    "proposal list", "승인을 기다리는 제안 목록. Claude 대화에서 아직 적용하지 않은 변경",
    discussion: """
        제안은 그 대화의 Claude 패널에서 승인한다. LMS에서 읽은 제안은 앱의 로그인으로만 읽으므로 이 목록에 없다.
        뒤 제안에 대체된 제안과 다른 기기가 이미 적용한 제안은 뺀다.
        """,
    examples: ["folio proposal list", "folio proposal list EC4207"],
    phrases: ["승인할 제안", "제안 목록", "기다리는 변경", "적용 안 한 제안"], panel: true)
public struct ProposalList {
    public struct Item: Encodable {
        public var id: String
        public var kind: ProposalKind
        public var course: UUID
        public var chat: UUID
        public var chatTitle: String
        public var proposal: UUID?
        public var command: String
        public var input: JSONValue
        public var summary: String
    }

    /// 과목. 빼면 모든 과목
    @Arg public var course: Course.ID?

    public func read(_ ctx: ReadContext) throws -> [Item] {
        let all = ctx.courses()
        let applied = Set(all.flatMap { $0.file.appliedProposals ?? [] })
        return all.filter { course == nil || $0.id == course }.flatMap { c in
            let chats = ((try? c.store.chats()) ?? []).map { $0.model.markingApplied(applied) }
            return chats.flatMap { $0.pending(course: c.id, targets: Actions.targets) }.compactMap { p -> Item? in
                guard case .claude(let source) = p.source else { return nil }
                return Item(
                    id: p.id, kind: p.kind, course: source.course, chat: source.chat, chatTitle: source.chatTitle,
                    proposal: source.proposal.id, command: source.proposal.command, input: source.proposal.input,
                    summary: Actions.summary(source.proposal, ctx: ctx.base) ?? source.proposal.command)
            }
        }
    }
}
