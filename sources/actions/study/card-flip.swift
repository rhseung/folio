import FolioDomain
import FolioStorage
import Foundation

@Action(
    "card flip", "카드를 넘겨 보고 알았는지 기록. 모르면 --unknown, 참거짓 카드는 --answer",
    discussion: "참거짓 카드는 고른 답을 --answer true나 --answer false로 준다. 카드의 답과 같으면 앎, 다르면 모름으로 기록한다.", effect: .logs,
    done: "카드 '{card}'을(를) 기록했습니다",
    examples: [
        #"folio card flip EC4207/매칭 "최대 매칭의 정의""#, #"folio card flip EC4207/매칭 "최대 매칭의 정의" --unknown"#,
        #"folio card flip EC4207/매칭 "모든 정규 이분 그래프에는 완전 매칭이 있다" --answer true"#,
    ],
    phrases: ["카드 외웠", "카드 몰랐", "참거짓 카드 답"],
    panel: true)
public struct CardFlip {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 카드 ID 또는 앞면 글
    @Arg var card: StudyCard.ID
    /// 몰랐음
    @Off("unknown") var known = true
    /// 참거짓 카드에서 고른 답. true 또는 false
    var answer: Bool?

    public func run(_ ctx: ActionContext) throws {
        guard let found = try ctx.store(course).loadCards(unit: unit).model.cards.first(where: { $0.id == card }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundItem(String(localized: .valueCard))))
        }
        switch (found.kind, answer) {
        case (.flip, nil): try ctx.log(CardFlipEvent(cardId: card, known: known), course: course)
        case (.trueFalse, let picked?):
            try ctx.log(CardFlipEvent(cardId: card, known: found.knows(picking: picked), answer: picked), course: course)
        case (.flip, .some): throw ActionError.input(String(localized: .errorCardAnswerOnFlip))
        case (.trueFalse, nil): throw ActionError.input(String(localized: .errorCardAnswerMissing))
        }
    }
}
