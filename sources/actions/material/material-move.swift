import FolioDomain
import FolioStorage
import Foundation

@Action(
    "material mv", "자료 파일을 옮기거나 이름 바꾸기. ID와 연결은 그대로", discussion: "moves.jsonl에 남겨서 folio cleanup undo로 되돌릴 수 있다.",
    effect: .moves, confirm: "{material}을(를) {to}(으)로 옮깁니다.", done: "{material}을(를) {to}(으)로 옮겼습니다",
    examples: ["folio material mv EC4207/Seating.pdf Exams/Midterm/자리.pdf --dry-run"],
    phrases: ["파일 이름 바꾸기", "다른 폴더로", "파일 이름 변경", "파일 옮기기"], undoable: true)
public struct MaterialMove {
    @Arg var course: Course.ID
    /// 자료
    @Arg var material: Material.ID
    /// 새 경로. 과목 폴더 기준
    @Arg var to: String

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try ctx.file(course)
        let m = file.materials[try index(material, in: file.materials, .valueMaterial)]
        guard store.contains(to) else { throw ActionError.rule(String(localized: .errorMaterialMoveOutside(to))) }
        let change = Change(.moved, try ctx.relative(course, m.path), to: try ctx.relative(course, to))
        if ctx.dryRun {
            ctx.record(change)
            return
        }
        try ctx.edit(course) { f in
            ctx.made(try store.move(material, to: to, gist: ctx.gist.url, in: &f, device: ctx.device, now: ctx.now))
        }
        ctx.record(change)
    }
}
