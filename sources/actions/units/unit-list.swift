import FolioDomain
import Foundation

@Query(
    "unit list", "과목의 단원 트리", examples: ["folio unit list EC4207", "folio unit list EC4207 --depth 1"],
    phrases: ["단원 목록", "챕터 목록", "진도"], panel: true, lines: true)
public struct UnitList {
    /// 과목. 강의 코드, 폴더 이름, 과목 이름, UUID
    @Arg public var course: Course.ID
    /// 보여 줄 깊이. 1이면 맨 위 단원만
    public var depth: Int?

    // 사람용 출력이 트리를 그리도록 깊이를 함께 두고, JSON은 단원만 차례로 쓴다.
    public struct Outline: Encodable {
        public var items: [(unit: FolioDomain.Unit, depth: Int)]
        public var file: CourseFile

        public func encode(to encoder: Encoder) throws { try items.map { QueryLinks($0.unit, in: file) }.encode(to: encoder) }
    }

    public func read(_ ctx: ReadContext) throws -> Outline {
        let f = try ctx.file(course)
        return Outline(items: UnitTree.outline(f.units).filter { item in depth.map { item.depth < $0 } ?? true }, file: f)
    }
}
