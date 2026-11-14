import FolioDomain
import FolioStorage
import Foundation

@Action(
    "assignment add", "과제 추가. 제목이 HW3처럼 표준 이름이면 Assignments 폴더도 만든다", effect: .creates, done: "과제 '{title}'을(를) 추가했습니다",
    examples: [
        #"folio assignment add EC4207 "HW 3" --due "2026-11-04 23:59""#,
        #"folio assignment add EC4207 "Weekly Quiz" --due 2026-11-02 --repeats weekly --dry-run"#,
        #"folio assignment add EC4207 "Lab 보고서" --due 2026-11-02 --repeats "격주 월수""#,
    ],
    phrases: ["과제 추가", "숙제 생김", "새 과제"])
public struct AssignmentAdd {
    @New var id: Assignment.ID
    /// 과목
    @Arg var course: Course.ID
    /// 과제 제목
    @Arg var title: String
    /// 마감 일시
    var due: Date?
    /// 반복. weekly, daily, biweekly, monthly, 3d, 2w, 1m, weekly:mon,wed, 또는 빠른 추가의 말(매일, 격일, 3일마다, 격주, 매월, 매주 월수, 월,수마다, 평일마다)
    var repeats: AssignmentRepeat?
    /// The LMS assignment it comes from (`LMSAssignment.id`), when added from the LMS proposals.
    @Hidden var lms: Int?

    public func run(_ ctx: ActionContext) throws {
        guard !title.isEmpty else { throw ActionError.rule(String(localized: .errorAssignmentTitleEmpty)) }
        try ctx.edit(course) { f in
            if let lms, let same = f.assignments.first(where: { $0.lmsId == lms }) {
                throw ActionError.rule(String(localized: .errorLmsAssignmentAdded(same.title)))
            }
            var a = Assignment(id: id, device: ctx.device, at: ctx.now, title: title, due: due, source: lms == nil ? .manual : .lms)
            a.repeats = repeats
            a.lmsId = lms
            f.assignments.append(a)
        }

        if AssignmentKind.parse(title: title) != nil {
            let path = AssignmentFiles.path(of: Assignment(device: ctx.device, at: ctx.now, title: title))
            let store = try ctx.store(course)
            if !FileManager.default.fileExists(atPath: store.fileURL(path).path) {
                try ctx.io(Change(.added, ctx.relative(store.fileURL(path)) + "/")) { try store.ensureFolder(assignmentTitle: title) }
            }
        }
        ctx.made(id)
    }
}
