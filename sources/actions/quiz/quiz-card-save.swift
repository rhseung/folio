import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

// MARK: Quiz

@Action(
    "quiz add", "JSON 파일의 카드를 넣거나 같은 ID의 카드를 바꾸기",
    discussion: "파일은 course.json과 같은 필드 이름을 쓰는 QuizCard 배열이다. 단원을 옮긴 카드는 --moved-from에 예전 단원을 준다.",
    done: "카드 {cards}을(를) 저장했습니다",
    examples: ["folio quiz add EC4207 --file cards.json", "folio quiz add EC4207 --file - --moved-from 매칭 < card.json"],
    phrases: ["카드 만들기", "퀴즈 추가"])
public struct QuizCardSave {
    /// 과목
    @Arg var course: Course.ID
    /// 카드 JSON 파일. -이면 표준 입력
    @CLIName("file") @FromFile var cards: [QuizCard]
    /// 카드가 떠난 단원
    var movedFrom: FolioDomain.Unit.ID?

    public func run(_ ctx: ActionContext) throws {
        let units = Set(try ctx.file(course).units.map(\.id))
        for unit in Set(cards.map(\.unitId)) {
            guard units.contains(unit) else { throw ActionError.notFound(String(localized: .errorNotFoundUnit)) }
            try ctx.editQuiz(course, unit: unit) { list in
                for var card in cards where card.unitId == unit {
                    card.touch(by: ctx.device, at: ctx.now)
                    if let i = list.firstIndex(where: { $0.id == card.id }) { list[i] = card } else { list.append(card) }
                }
            }
        }
        if let movedFrom, !cards.contains(where: { $0.unitId == movedFrom }) {
            let ids = Set(cards.map(\.id))
            try ctx.editQuiz(course, unit: movedFrom) { $0.removeAll { ids.contains($0.id) } }
        }
    }
}
