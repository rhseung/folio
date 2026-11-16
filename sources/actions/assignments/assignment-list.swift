import FolioDomain
import Foundation

@Query(
    "assignment list", "과목의 과제 목록. 기본은 아직 낼 것만",
    examples: ["folio assignment list EC4207", "folio assignment list EC4207 --all --lines"],
    phrases: ["과제 목록", "숙제 뭐 남았지", "할 일 목록"], panel: true, lines: true)
public struct AssignmentList {
    /// 과목. 강의 코드, 폴더 이름, 과목 이름, UUID
    @Arg public var course: Course.ID
    /// 낸 것과 채점된 것까지
    public var all = false

    public func read(_ ctx: ReadContext) throws -> [Assignment] {
        try ctx.file(course).assignments.filter { all || $0.status == .todo || $0.status == .doing }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }
}
