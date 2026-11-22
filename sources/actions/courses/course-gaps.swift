import FolioDomain
import Foundation

@Query(
    "course gaps", "계산으로 채울 수 없는 빠진 연결: 단원 쪽 구간이 없는 렉처, 범위를 계산할 수 없는 시험, 걸 데 없는 노트, 매달린 연결",
    discussion: """
        회차의 단원, 렉처의 배운 범위, 시험 범위는 진도 쪽과 단원 쪽 구간에서 계산하므로 이 목록에 없다. 이 목록의 빈자리를
        채우면 그 계산이 돌아간다. 자유 노트는 걸 데가 없는 것이 맞아 세지 않는다.
        """,
    examples: ["folio course gaps", "folio course gaps EC4207 --json"],
    phrases: ["빠진 연결", "연결 안 된 것", "매달린 연결", "범위를 못 정하는 시험"], panel: true)
public struct CourseGaps {
    public struct Item: Encodable {
        public var course: UUID
        public var gap: CourseLinkGap
        public var dangling: Bool
        public var summary: String
    }

    /// 과목. 빼면 모든 과목
    @Arg public var course: Course.ID?

    public func read(_ ctx: ReadContext) throws -> [Item] {
        ctx.courses().filter { course == nil || $0.id == course }.flatMap { c in
            c.file.linkGaps(now: ctx.now, today: ctx.today, calendar: ctx.calendar).map {
                Item(course: c.id, gap: $0, dangling: $0.isDangling, summary: c.file.describe($0, calendar: ctx.calendar))
            }
        }
    }
}
