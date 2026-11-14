import FolioDomain
import FolioStorage
import Foundation

// 가져온 평가 항목은 같은 `order`를 가질 수 있으므로 모두 번호를 다시 매긴다.
@Action(
    "component move", "성적 항목을 한 칸 위나 아래로", done: "성적 항목 '{component}'을(를) 옮겼습니다",
    cli: .manual(reason: "--up과 --down 플래그가 옮길 칸 수(by)가 된다"))
public struct ComponentMove {
    @Arg var course: Course.ID
    @Arg var component: GradeComponent.ID
    /// -1이면 위로, 1이면 아래로
    var by: Int

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            var ids = f.components.sorted { $0.order < $1.order }.map(\.id)
            guard let i = ids.firstIndex(of: component) else { throw ActionError.notFound(String(localized: .errorNotFoundComponent)) }
            guard ids.indices.contains(i + by) else { return }
            ids.swapAt(i, i + by)
            for j in f.components.indices {
                let order = ids.firstIndex(of: f.components[j].id)!
                if f.components[j].order != order {
                    f.components[j].order = order
                    f.components[j].touch(by: ctx.device, at: ctx.now)
                }
            }
        }
    }
}
