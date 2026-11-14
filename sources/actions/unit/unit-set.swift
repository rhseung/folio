import FolioDomain
import FolioStorage
import Foundation

@Action(
    "unit set", "단원 제목 바꾸기", done: "단원 '{unit}'의 제목을 바꿨습니다",
    examples: [#"folio unit set EC4207/트리 --title "트리와 숲""#], phrases: ["단원 제목", "단원 이름 바꾸기", "챕터 이름"])
public struct UnitSet {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 새 제목
    var title: String

    public func run(_ ctx: ActionContext) throws {
        let name = title.trimmingCharacters(in: .whitespaces)
        try ctx.edit(course) { f in
            try f.update(\.units, unit) { u in
                guard u.title != name else { return }
                u.title = name
                u.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
