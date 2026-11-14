import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Verdict: ExpressibleByArgument {}
extension QuizAttemptEvent.Grader: ExpressibleByArgument {}

extension Resolver {
    func card(_ ref: String, unit: FolioDomain.Unit, in c: CourseRef) throws -> QuizCard {
        let store = c.store
        return try pick(ref, try store.loadQuiz(unit: unit.id).model.cards, what: "카드", names: { [$0.prompt] }, ref: { $0.id.uuidString })
    }
}
