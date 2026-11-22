import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam plan make", "범위 단원의 준비 정도로 시험까지 공부 계획을 다시 짜기. 직접 고치거나 더한 항목은 그대로 둔다",
    discussion: "앱은 공부일이 바뀐 뒤 처음 열 때 이것을 부른다. 못 한 지난 단원은 오늘로 옮기고, 마지막 날들은 섞어 풀기, 모의시험, 오답 다시 보기로 둔다.",
    done: "시험 '{exam}'의 공부 계획을 짰습니다", examples: ["folio exam plan make EC4207/중간고사 --dry-run"], phrases: ["공부 계획 짜", "계획 다시", "시험 계획 세워"],
    panel: true)
public struct ExamPlanMake {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID

    public func run(_ ctx: ActionContext) throws {
        let study = try ctx.study(course)
        let settings = try ctx.settings()
        guard let e = try ctx.file(course).exams.first(where: { $0.id == exam }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundItem(String(localized: .valueExam))))
        }
        guard let plan = study.replan(e, calendar: ctx.calendar, settings: settings) else {
            throw ActionError.rule(String(localized: .errorPlanNeedsExamTime))
        }
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                guard e.plan != plan || e.planDay != study.today else { return }
                e.plan = plan
                e.planDay = study.today
                e.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
