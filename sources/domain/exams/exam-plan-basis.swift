import FolioCore
import Foundation

// 계획을 짠 기준이다. 시험에 저장해 두고, 범위나 시험 날짜나 계획에 쓰는 공부 설정이 바뀌면 같은 공부일에도 다시 짠다.
// 준비 점수는 문제를 풀 때마다 바뀌므로 넣지 않는다. 넣으면 하루 중에 계획이 자꾸 바뀐다.
public struct ExamPlanBasis: Codable, Sendable, Equatable, Hashable {
    public var scope: [UUID]
    public var examDay: LocalDate?
    public var readyPercent: Int
    public var minProblems: Int
    public var finalDays: Int
    public var dayItems: Int

    public init(exam: Exam, settings: Settings, calendar: Calendar) {
        scope = exam.scopeUnitIds
        examDay = exam.start.map { settings.studyDay(of: $0, calendar: calendar) }
        readyPercent = settings.study.readyPercent
        minProblems = settings.study.minProblems
        finalDays = settings.study.finalDays
        dayItems = settings.study.planDayItems
    }
}

extension Exam {
    // 공부일이 바뀌었거나 기준이 바뀐 다가오는 시험만 다시 짠다.
    public func needsPlan(today: LocalDate, settings: Settings, calendar: Calendar) -> Bool {
        guard !scopeUnitIds.isEmpty, let start, settings.studyDay(of: start, calendar: calendar) >= today else { return false }
        return planDay != today || planBasis != ExamPlanBasis(exam: self, settings: settings, calendar: calendar)
    }
}
