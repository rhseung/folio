import FolioActions
import FolioDomain
import Foundation

extension CardList: QueryLines {
    func lines(_ found: Decks, _ r: Resolver) throws -> [[String]] {
        found.decks.flatMap { u, cards in cards.map { [$0.id.uuidString, u.title, $0.front] } }
    }

    func say(_ found: Decks, _ r: Resolver) throws {
        courseHeader(try r.course(id: course), catalog: try? r.ctx.catalog())
        var t = Table(
            header: [
                String(localized: .cardListHeaderUnit), String(localized: .cardListHeaderFront), String(localized: .cardListHeaderBack),
            ],
            shrink: [1, 2])
        for (u, cards) in found.decks {
            for card in cards { t.rows.append([u.title, card.front, card.back]) }
        }
        t.print()
        footer(found.decks.map(\.cards.count).reduce(0, +))
    }
}
