import FolioDomain
import Foundation

@Query(
    "material list", "과목의 자료 목록", examples: ["folio material list EC4207", "folio material list EC4207 --lines"],
    phrases: ["자료 목록", "강의자료 보기", "파일 목록"], panel: true, lines: true)
public struct MaterialList {
    /// 과목
    @Arg public var course: Course.ID
    /// 무시한 자료까지
    public var all = false

    public func read(_ ctx: ReadContext) throws -> [Material] {
        try ctx.file(course).materials.sorted { $0.path < $1.path }.filter { all || $0.status != .ignored }
    }
}
