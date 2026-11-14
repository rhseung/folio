import FolioDomain
import FolioStorage
import Foundation

@Action(
    "assignment rm", "과제와 그 점수 지우기. 과제 폴더와 파일은 남는다", effect: .removes,
    confirm: "과제 '{assignment}'과(와) 그 점수를 지웁니다. 폴더와 파일은 남습니다.", done: "과제 '{assignment}'을(를) 지웠습니다",
    examples: ["folio assignment rm EC4207/HW3 --dry-run"], phrases: ["과제 삭제", "과제 지우기"])
public struct AssignmentRemove {
    /// 과목
    @Arg var course: Course.ID
    /// 과제
    @Arg var assignment: Assignment.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(assignment, in: f.assignments, .valueAssignment)
            try f.remove(Assignment.self, assignment)
        }
    }
}
