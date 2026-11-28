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
                String(localized: .cardListHeaderUnit), String(localized: .cardListHeaderKind), String(localized: .cardListHeaderFront),
                String(localized: .cardListHeaderBack), String(localized: .cardListHeaderNote),
            ],
            shrink: [4, 2, 3])
        for (u, cards) in found.decks {
            for card in cards { t.rows.append([u.title, kind(card), card.front, back(card), place(card, in: found)]) }
        }
        t.print()
        footer(found.decks.map(\.cards.count).reduce(0, +))
    }

    private func kind(_ card: StudyCard) -> String {
        switch card.kind {
        case .flip: String(localized: .cardKindFlip)
        case .trueFalse: String(localized: .cardKindTrueFalse)
        }
    }

    // 참거짓 카드의 뒷면은 답과 이유다.
    private func back(_ card: StudyCard) -> String {
        guard card.kind == .trueFalse, let answer = card.answer else { return card.back }
        return String(localized: answer ? .cardListTrue(card.back) : .cardListFalse(card.back))
    }

    private func place(_ card: StudyCard, in found: Decks) -> String {
        guard let note = card.noteId.flatMap({ found.notes[$0] }) else { return "" }
        return card.noteSection.map { "\(note) › \($0)" } ?? note
    }
}
