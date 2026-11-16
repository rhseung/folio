import FolioActions
import FolioDomain
import Foundation

extension ProposalList: QueryOutput {
    func say(_ items: [Item], _ r: Resolver) throws {
        var t = Table(
            header: [
                "", String(localized: .proposalListHeaderChat), String(localized: .proposalListHeaderChange),
                String(localized: .proposalListHeaderCommand),
            ], shrink: [1, 2])
        for i in items {
            let c = try? r.course(id: i.course)
            t.rows.append([c.map { "●".course($0.color) + " " + $0.tag } ?? "", i.chatTitle, i.summary, i.command.styled(.dim)])
        }
        t.print()
        footer(items.count)
    }
}
