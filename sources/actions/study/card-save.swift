import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "card add", "JSON 파일의 카드를 넣거나 같은 ID의 카드를 바꾸기",
    discussion: "파일은 StudyCard 배열이다(unitId, front, back, source). 단원을 옮긴 카드는 --moved-from에 예전 단원을 준다.",
    done: "카드 {cards}을(를) 저장했습니다",
    examples: ["folio card add EC4207 --file cards.json", "folio card add EC4207 --file - --moved-from 매칭 < card.json"],
    phrases: ["카드 만들기", "암기 카드", "개념 카드"], panel: true)
public struct CardSave {
    @Arg var course: Course.ID
    /// 카드 JSON 파일. -이면 표준 입력
    @CLIName("file") @FromFile var cards: [StudyCard]
    /// 카드가 떠난 단원
    var movedFrom: FolioDomain.Unit.ID?

    public func run(_ ctx: ActionContext) throws {
        let units = Set(try ctx.file(course).units.map(\.id))
        for unit in Set(cards.map(\.unitId)) {
            guard units.contains(unit) else { throw ActionError.notFound(String(localized: .errorNotFoundUnit)) }
            try ctx.editCards(course, unit: unit) { list in
                for var card in cards where card.unitId == unit {
                    card.touch(by: ctx.device, at: ctx.now)
                    if let i = list.firstIndex(where: { $0.id == card.id }) { list[i] = card } else { list.append(card) }
                }
            }
        }
        if let movedFrom, !cards.contains(where: { $0.unitId == movedFrom }) {
            let ids = Set(cards.map(\.id))
            try ctx.editCards(course, unit: movedFrom) { $0.removeAll { ids.contains($0.id) } }
        }
    }
}
