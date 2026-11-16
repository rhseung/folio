import FolioDomain
import Foundation

@Query(
    "session list", "과목의 회차 목록", examples: ["folio session list EC4207", "folio session list EC4207 --lines"],
    phrases: ["수업 목록", "강의 목록", "회차 보기", "몇 주차"], panel: true, lines: true)
public struct SessionList {
    /// 과목. 강의 코드, 폴더 이름, 과목 이름, UUID
    @Arg public var course: Course.ID
    /// 휴강한 회차까지
    public var all = false

    public func read(_ ctx: ReadContext) throws -> [Session] {
        try ctx.file(course).sessions.sorted { $0.date < $1.date }.filter { all || !$0.isCancelled }
    }
}
