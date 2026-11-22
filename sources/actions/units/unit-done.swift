import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "unit done", "단원을 다 한 것으로 표시, --undo면 풀기", done: "단원 '{unit}'의 표시를 바꿨습니다",
    examples: ["folio unit done EC4207/매칭", "folio unit done EC4207/매칭 --undo"], phrases: ["단원 다 했", "단원 끝", "단원 완료"], panel: true)
public struct UnitDone {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    @Off("undo") var done = true

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.units, unit) { u in
                guard u.isDone != done else { return }
                u.isDone = done
                u.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
