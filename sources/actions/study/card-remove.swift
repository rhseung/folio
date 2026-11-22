import FolioDomain
import FolioStorage
import Foundation

@Action(
    "card rm", "카드 지우기. 넘긴 기록은 남는다", effect: .removes, confirm: "단원 '{unit}'의 카드 '{card}'을(를) 지웁니다. 넘긴 기록은 남습니다.",
    done: "단원 '{unit}'의 카드를 지웠습니다", examples: [#"folio card rm EC4207/매칭 "최대 매칭의 정의""#], phrases: ["카드 삭제"], panel: true)
public struct CardRemove {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 카드 ID 또는 앞면 글
    @Arg var card: StudyCard.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.editCards(course, unit: unit) { list in
            _ = try index(card, in: list, .valueCard)
            list.removeAll { $0.id == card }
        }
    }
}
