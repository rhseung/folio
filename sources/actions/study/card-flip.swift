import FolioDomain
import FolioStorage
import Foundation

@Action(
    "card flip", "카드를 넘겨 보고 알았는지 기록. 모르면 --unknown", effect: .logs, done: "카드 '{card}'을(를) 기록했습니다",
    examples: [#"folio card flip EC4207/매칭 "최대 매칭의 정의""#, #"folio card flip EC4207/매칭 "최대 매칭의 정의" --unknown"#],
    phrases: ["카드 외웠", "카드 몰랐"],
    panel: true)
public struct CardFlip {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 카드 ID 또는 앞면 글
    @Arg var card: StudyCard.ID
    /// 몰랐음
    @Off("unknown") var known = true

    public func run(_ ctx: ActionContext) throws {
        guard try ctx.store(course).loadCards(unit: unit).model.cards.contains(where: { $0.id == card }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundItem(String(localized: .valueCard))))
        }
        try ctx.log(CardFlipEvent(cardId: card, known: known), course: course)
    }
}
