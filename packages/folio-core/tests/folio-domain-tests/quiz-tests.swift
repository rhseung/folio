import FolioDomain
import Foundation
import Testing

struct QuizTests {
    func d(_ s: String) -> LocalDate { LocalDate(s)! }

    @Test func wrongResolvedAndRecheck() {
        #expect(WrongFlow.status([]) == .neverWrong)
        #expect(WrongFlow.status([(d("2026-10-01"), .correct)]) == .neverWrong)
        #expect(WrongFlow.status([(d("2026-10-01"), .partial)]) == .open(since: d("2026-10-01")))
        let resolved = WrongFlow.status([(d("2026-10-01"), .wrong), (d("2026-10-03"), .correct)])
        #expect(resolved == .resolved(on: d("2026-10-03"), recheckDue: d("2026-10-10")))
        // Wrong again at the recheck: back to open.
        #expect(WrongFlow.status([(d("2026-10-01"), .wrong), (d("2026-10-03"), .correct), (d("2026-10-10"), .wrong)]) == .open(since: d("2026-10-10")))
        // Correct at the recheck: done, no further recheck.
        #expect(WrongFlow.status([(d("2026-10-01"), .wrong), (d("2026-10-03"), .correct), (d("2026-10-11"), .correct)])
            == .resolved(on: d("2026-10-03"), recheckDue: nil))
        // A correct answer before the recheck day doesn't count as the recheck.
        #expect(WrongFlow.status([(d("2026-10-01"), .wrong), (d("2026-10-03"), .correct), (d("2026-10-05"), .correct)])
            == .resolved(on: d("2026-10-03"), recheckDue: d("2026-10-10")))
    }

    @Test func picksOpenAndRecheckDueFirstThenStale() {
        let open = UUID(), recheck = UUID(), stale = UUID(), fresh = UUID(), never = UUID()
        let attempts: [UUID: [(day: LocalDate, verdict: Verdict)]] = [
            open: [(d("2026-10-20"), .wrong)],
            recheck: [(d("2026-10-01"), .wrong), (d("2026-10-05"), .correct)],
            stale: [(d("2026-09-01"), .correct)],
            fresh: [(d("2026-10-21"), .correct)],
        ]
        let picked = WrongFlow.pickForReview(cards: [fresh, stale, open, recheck, never], attempts: attempts, today: d("2026-10-22"), count: 4)
        #expect(Array(picked.prefix(2)) == [open, recheck])
        #expect(picked[2] == never && picked[3] == stale)
    }

    @Test func accuracyCountsPartialAsHalf() {
        #expect(WrongFlow.accuracy([.correct, .partial, .wrong, .correct]) == 0.625)
        #expect(WrongFlow.accuracy([]) == nil)
    }

    func card(_ unit: UUID, _ category: CardCategory = .definition) -> QuizCard {
        QuizCard(device: UUID(), at: .now, unitId: unit, type: .free, category: category, prompt: "", answer: "")
    }

    @Test func deckFiltersByScopeAndOrders() {
        let u1 = UUID(), u2 = UUID(), u3 = UUID()
        // File order puts a u2 card first; unit order must still lead with u1.
        let a = card(u2, .proof), b = card(u1), c = card(u1, .theorem), x = card(u3), e = card(u2)
        let history: [UUID: AttemptHistory] = [
            c.id: [(d("2026-10-20"), .wrong)],
            e.id: [(d("2026-10-01"), .wrong), (d("2026-10-02"), .correct)],  // recheck due 10-09
            a.id: [(d("2026-10-20"), .correct)],
        ]
        var rng = SystemRandomNumberGenerator()
        let today = d("2026-10-22")
        func ids(_ scope: QuizScope, _ order: QuizOrder) -> [UUID] {
            QuizDeck.build(cards: [a, b, c, x, e], units: [u1, u2, u3], scope: scope, order: order, history: history, today: today, using: &rng).map(\.id)
        }
        #expect(ids(QuizScope(unitIds: [u1, u2]), .unitOrder) == [b.id, c.id, a.id, e.id])
        #expect(ids(QuizScope(unitIds: [u1, u2]), .wrongFirst) == [c.id, e.id, b.id, a.id])
        #expect(ids(QuizScope(unitIds: [u1, u2, u3], onlyWrong: true), .unitOrder) == [c.id, e.id])
        #expect(ids(QuizScope(unitIds: [u1, u2], categories: [.proof, .theorem]), .unitOrder) == [c.id, a.id])
        #expect(Set(ids(QuizScope(unitIds: [u1, u2, u3]), .random)) == Set([a, b, c, x, e].map(\.id)))
    }

    @Test func statsFoldOpenResolvedAndAccuracy() {
        let u1 = UUID(), u2 = UUID()
        let cards = [card(u1, .proof), card(u1), card(u2), card(u2, .proof)]
        let history: [UUID: AttemptHistory] = [
            cards[0].id: [(d("2026-10-01"), .wrong)],
            cards[1].id: [(d("2026-10-01"), .partial), (d("2026-10-02"), .correct)],
            cards[2].id: [(d("2026-10-01"), .correct)],
        ]
        let byUnit = QuizStats.tally(cards, keys: { [$0.unitId] }, history: { history[$0.id] ?? [] })
        #expect(byUnit[u1]?.items == 2 && byUnit[u1]?.open == 1 && byUnit[u1]?.resolved == 1)
        #expect(byUnit[u1]?.accuracy == 0.5)  // wrong 0 + partial 0.5 + correct 1 over 3 attempts
        #expect(byUnit[u2]?.attempted == 1 && byUnit[u2]?.correct == 1 && byUnit[u2]?.progress == 0.5)
        let byCategory = QuizStats.tally(cards, keys: { [$0.category] }, history: { history[$0.id] ?? [] })
        #expect(byCategory[.proof]?.open == 1 && byCategory[.proof]?.items == 2)
        let total = QuizStats.total(cards) { history[$0.id] ?? [] }
        #expect(total.items == 4 && total.open == 1 && total.resolved == 1 && total.correct == 1)
        // A problem in two units counts in both.
        let shared = ProblemSet.Problem(number: "3", unitIds: [u1, u2])
        let multi = QuizStats.tally([shared], keys: \.unitIds, history: { _ in [(d("2026-10-01"), .wrong)] })
        #expect(multi[u1]?.open == 1 && multi[u2]?.open == 1)
    }

    @Test func problemNumbersParse() {
        #expect(ProblemSet.numbers(from: "1-3, 5 8a, 2") == ["1", "2", "3", "5", "8a"])
        #expect(ProblemSet.numbers(from: "") == [])
        #expect(ProblemSet.numbers(from: "1-100000") == ["1-100000"])
    }
}
