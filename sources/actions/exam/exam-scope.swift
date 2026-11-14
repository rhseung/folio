import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam scope", "시험 범위에 단원 넣기, --off면 빼기", done: "시험 '{exam}'의 범위를 바꿨습니다",
    cli: .manual(reason: "--unit마다 액션을 한 번씩 같은 맥락에서 돌려 결과를 하나로 보이고, --taught면 exam scope --taught를 돌린다"))
public struct ExamScope {
    @Arg var course: Course.ID
    @Arg var exam: Exam.ID
    /// 단원
    var unit: FolioDomain.Unit.ID
    /// 범위에서 빼기
    @Off("off") var included = true

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            let e = try index(exam, in: f.exams, .valueExam)
            _ = try index(unit, in: f.units, .valueUnit)
            if f.exams[e].scopeUnitIds.contains(unit) != included { f.toggle(exam: exam, unit: unit) }
        }
    }
}
