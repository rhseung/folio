import FolioDomain
import FolioStorage
import Foundation

// MARK: Units

@Action(
    "unit add", "단원 추가. 형제 단원 맨 뒤에 놓인다", effect: .creates, done: "단원 '{title}'을(를) 추가했습니다",
    examples: ["folio unit add EC4207 트리", #"folio unit add EC4207 "스패닝 트리" --parent 트리 --dry-run"#],
    phrases: ["단원 추가", "챕터 추가", "새 단원"])
public struct UnitAdd {
    @New var id: FolioDomain.Unit.ID
    /// 과목
    @Arg var course: Course.ID
    /// 단원 제목
    @Arg var title: String
    /// 상위 단원. 없으면 맨 위
    var parent: FolioDomain.Unit.ID?

    public func run(_ ctx: ActionContext) throws {
        let name = title.trimmingCharacters(in: .whitespaces)
        try ctx.edit(course) { f in
            guard !f.units.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenUnit("\(id)"))) }
            f.units.append(
                FolioDomain.Unit(
                    id: id, device: ctx.device, at: ctx.now, title: name, order: UnitTree.nextOrder(under: parent, in: f.units),
                    parentId: parent))
        }
        ctx.made(id)
    }
}
