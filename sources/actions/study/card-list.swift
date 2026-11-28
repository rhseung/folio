import FolioDomain
import FolioStorage
import Foundation

@Query(
    "card list", "단원별 카드",
    examples: ["folio card list EC4207", "folio card list EC4207 --unit 매칭", #"folio card list EC4207 --note "매칭 정리""#],
    phrases: ["카드 보기", "암기 카드", "노트의 카드"],
    panel: true, lines: true)
public struct CardList {
    /// 과목
    @Arg public var course: Course.ID
    /// 이 단원만
    public var unit: FolioDomain.Unit.ID?
    /// 이 노트에 이은 카드만
    public var note: Note.ID?

    // JSON은 카드만 차례로 쓰고, 단원과 노트 이름은 사람용 출력이 쓴다.
    public struct Decks: Encodable {
        public var decks: [(unit: FolioDomain.Unit, cards: [StudyCard])]
        public var notes: [UUID: String]

        public func encode(to encoder: Encoder) throws { try decks.flatMap(\.cards).encode(to: encoder) }
    }

    public func read(_ ctx: ReadContext) throws -> Decks {
        let file = try ctx.file(course)
        let store = try ctx.store(course)
        let units = unit.map { id in file.units.filter { $0.id == id } } ?? file.units
        let decks = try units.map { unit in
            (unit, try store.loadCards(unit: unit.id).model.cards.filter { note == nil || $0.noteId == note })
        }
        return Decks(
            decks: decks.filter { !$0.1.isEmpty }, notes: Dictionary(file.notes.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a }))
    }
}
