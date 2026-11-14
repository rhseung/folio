import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam set", "시험의 제목, 일시, 장소, 성적 항목, 범위 바꾸기. 준 것만 바뀐다. 제목을 바꿔도 시험 폴더는 그대로다", done: "시험 '{exam}'을(를) 바꿨습니다",
    examples: [
        #"folio exam set EC4207/중간고사 --start "2026-10-22 10:00" --end "2026-10-22 12:00""#,
        "folio exam set EC4207/Quiz1 --location B203", "folio exam set EC4207/Quiz1 --end none --component none --dry-run",
    ],
    phrases: ["시험 날짜 변경", "시험 시간", "시험 장소", "고사실"])
public struct ExamSet {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID
    /// 새 제목
    var title: Patch<String>
    /// 시작 일시
    var start: Patch<Date?>
    /// 끝 일시
    var end: Patch<Date?>
    /// 장소
    var location: Patch<String>
    /// 반영되는 성적 항목
    var component: Patch<GradeComponent.ID?>
    /// 범위 단원 전체. 단원을 하나씩 넣고 빼려면 folio exam scope
    var scope: Patch<[FolioDomain.Unit.ID]>
    /// 범위 설명
    var scopeText: Patch<String>
    /// 허용 자료
    var allowed: Patch<String>
    /// 메모
    var memo: Patch<String>

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                title.apply(&e.title)
                start.apply(&e.start)
                end.apply(&e.end)
                location.apply(&e.location)
                component.apply(&e.componentId)
                scopeText.apply(&e.scopeText)
                allowed.apply(&e.allowed)
                memo.apply(&e.memo)
                e.touch(by: ctx.device, at: ctx.now)
            }
            if let scope = scope.value { f.setScope(scope, exam: exam) }
        }
    }
}
