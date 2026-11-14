import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "quiz rm", "카드 지우기. 풀이 기록은 남는다", effect: .removes, confirm: "단원 '{unit}'의 카드를 지웁니다. 풀이 기록은 남습니다.",
    done: "단원 '{unit}'의 카드를 지웠습니다", examples: ["folio quiz rm EC4207/매칭 3F2A9C1E-0000-4000-8000-000000000001"], phrases: ["카드 삭제"])
public struct QuizCardRemove {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 카드 ID 또는 문제 글
    @Arg var card: QuizCard.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.editQuiz(course, unit: unit) { list in
            _ = try index(card, in: list, .valueCard)
            list.removeAll { $0.id == card }
        }
    }
}
