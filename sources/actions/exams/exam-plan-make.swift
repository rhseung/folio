import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "exam plan make", "시험의 정리 노트를 공부 기간에 놓기. 기간을 주면 그 기간으로 바꾼다. 끝낸 항목과 직접 옮기거나 더하거나 뺀 항목은 그대로 둔다",
    discussion:
        "정리 노트는 시험 범위의 단원에 이은 낱개 노트(topic)이고 이름 순서대로 놓인다. 노트마다 같은 날에 정독, 증명, 문제풀이를 두고, 증명은 정리류 블록(정리, 명제, 따름정리, 보조정리)이 있는 노트에만 둔다. 정리 노트가 없는 범위 단원은 첫날에 정리 노트 만들기로 놓인다. 기간을 빼면 저장한 기간이고, 처음이면 오늘부터 시험 전날이다. 시험 전날에 끝나는 기간은 시험 날짜가 바뀌면 새 시험 전날로 따라간다. --after mock이면 끝낼 날 다음 날부터 시험 전날까지 하루 한 벌씩 족보 묶음 수만큼 모의고사를 둔다. 앱은 계획이 없을 때와 기간, 정리 노트 목록, 시험 날짜가 바뀔 때 이것을 부른다. 공부일이 바뀌었다고 다시 놓지 않는다.",
    done: "시험 '{exam}'의 공부 계획을 놓았습니다",
    examples: [
        "folio exam plan make EC4207/기말고사 --dry-run", "folio exam plan make EC4207/기말고사 --start 2026-11-28 --end 2026-12-04 --after mock",
    ],
    phrases: ["공부 계획 짜", "계획 다시", "시험 계획 세워", "공부 기간", "기간 정하기"], panel: true)
public struct ExamPlanMake {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID
    /// 공부를 시작하는 날. 2026-11-28
    var start: LocalDate?
    /// 끝낼 날. 시험 전날까지. 2026-12-04
    var end: LocalDate?
    /// 끝낼 날 뒤의 날에 둘 것. empty(비움), mock(모의고사)
    var after: ExamPlanPeriod.After?

    public func run(_ ctx: ActionContext) throws {
        let study = try ctx.study(course)
        let settings = try ctx.settings()
        let file = study.file
        let e = file.exams[try index(exam, in: file.exams, .valueExam)]
        let examDay = try ctx.examDay(of: e)
        var period = e.fittedPeriod(today: study.today, examDay: examDay)
        if let start { period.start = start }
        if let end { period.end = end }
        if let after { period.after = after }
        // 시험 날짜가 바뀌어 맞춘 기간은 조용히 쓰지만, 지금 준 날짜가 틀리면 알린다.
        if start != nil || end != nil {
            guard period.isValid else { throw ActionError.rule(String(localized: .errorPlanPeriodOrder)) }
            guard period.end < examDay else { throw ActionError.rule(String(localized: .errorPlanPeriodPastExam)) }
        }
        let proofs = ExamPlanProofs.read(file.examNotes(of: e), store: try ctx.store(course), settings: settings)
        guard let placed = study.place(e, period: period, proofs: proofs, settings: settings, calendar: ctx.calendar) else { return }
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                guard e.plan != placed.plan || e.planPeriod != placed.period || e.planBasis != placed.basis else { return }
                e.plan = placed.plan
                e.planPeriod = placed.period
                e.planBasis = placed.basis
                e.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
