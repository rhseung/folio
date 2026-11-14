import FolioDomain
import FolioStorage
import Foundation

@Action(
    "material track", "과목 폴더의 새 파일을 등록하고 과제 폴더에 과제를 만든다",
    discussion: "옮기거나 이름을 바꾸지 않는다. 과목을 빼면 모든 과목에 한다. 지난 학기의 새 과제는 제출함으로 둔다.", done: "자료를 등록했습니다",
    examples: ["folio material track EC4207", "folio material track --dry-run"],
    phrases: ["새 파일 등록", "파일 스캔", "자료 반영"])
public struct MaterialTrack {
    /// 과목. 빼면 모든 과목
    @Arg var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        let courses = try course.map { [$0] } ?? ctx.gist.courseStores().map { try $0.load().model.course.id }
        let today = LocalDate(ctx.now, in: ctx.calendar)
        for course in courses {
            let store = try ctx.store(course)
            let folders = try store.assignmentFolders()
            let ended = try ctx.semester(of: ctx.file(course).course)?.end.map { $0 < today } ?? false
            try ctx.edit(course) { f in
                try store.refreshMaterials(in: &f, device: ctx.device, now: ctx.now)
                for title in AssignmentKind.unmatchedFolders(folders, assignments: f.assignments) {
                    var a = Assignment(device: ctx.device, at: ctx.now, title: title)
                    if ended { a.status = .submitted }
                    f.assignments.append(a)
                }
            }
        }
    }
}
