import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "quiz record", "카드 풀이 결과를 기록", effect: .logs, done: "풀이를 기록했습니다",
    phrases: ["맞았", "틀렸", "맞힘", "퀴즈 풀이", "맞음", "틀림", "카드 결과"],
    cli: .manual(reason: "단원 안에서 카드를 찾고, 판정, 채점자, 답으로 풀이 기록(QuizAttemptEvent) 하나를 만든다"))
public struct QuizRecord {
    @Arg var course: Course.ID
    var attempt: QuizAttemptEvent

    public func run(_ ctx: ActionContext) throws {
        let units = try ctx.file(course).units
        guard try units.contains(where: { try ctx.store(course).loadQuiz(unit: $0.id).model.cards.contains { $0.id == attempt.cardId } })
        else {
            throw ActionError.notFound(String(localized: .errorNotFoundCard))
        }
        try ctx.log(attempt, course: course)
    }
}
