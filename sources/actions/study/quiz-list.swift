import FolioDomain
import FolioStorage
import Foundation

@Query(
    "quiz list", "단원별 퀴즈 카드", examples: ["folio quiz list EC4207", "folio quiz list EC4207 --unit 매칭"],
    phrases: ["퀴즈 카드 보기", "암기 카드"], panel: true, lines: true)
public struct QuizList {
    /// 과목
    @Arg public var course: Course.ID
    /// 이 단원만
    public var unit: FolioDomain.Unit.ID?

    // JSON은 카드만 차례로 쓰고, 단원은 사람용 출력이 쓴다.
    public struct Decks: Encodable {
        public var decks: [(unit: FolioDomain.Unit, cards: [QuizCard])]

        public func encode(to encoder: Encoder) throws { try decks.flatMap(\.cards).encode(to: encoder) }
    }

    public func read(_ ctx: ReadContext) throws -> Decks {
        let file = try ctx.file(course)
        let store = try ctx.store(course)
        let units = unit.map { id in file.units.filter { $0.id == id } } ?? file.units
        return Decks(decks: try units.map { ($0, try store.loadQuiz(unit: $0.id).model.cards) }.filter { !$0.cards.isEmpty })
    }
}
