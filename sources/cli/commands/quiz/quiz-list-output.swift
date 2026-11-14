import FolioActions
import FolioDomain
import Foundation

extension QuizList: QueryLines {
    func lines(_ found: Decks, _ r: Resolver) throws -> [[String]] {
        found.decks.flatMap { u, cards in cards.map { [$0.id.uuidString, u.title, $0.type.rawValue, $0.prompt] } }
    }

    func say(_ found: Decks, _ r: Resolver) throws {
        courseHeader(try r.course(id: course), catalog: try? r.ctx.catalog())
        var t = Table(
            header: [
                String(localized: .quizListHeaderUnit), String(localized: .quizListHeaderKind),
                String(localized: .quizListHeaderCategory), String(localized: .quizListHeaderPrompt),
            ], shrink: [3])
        for (u, cards) in found.decks {
            for card in cards { t.rows.append([u.title, card.type.rawValue, card.category.rawValue, card.prompt]) }
        }
        t.print()
        footer(found.decks.map(\.cards.count).reduce(0, +))
    }
}
