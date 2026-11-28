import FolioCore
import Foundation

// 계획을 놓은 기준이다. 시험에 저장해 두고, 기간, 기간 뒤, 정리 노트 목록, 시험 날짜 가운데 하나가 바뀔 때만 다시 놓는다.
// 공부일은 기준이 아니다. 날이 바뀔 때마다 다시 놓으면 못 한 항목이 뒤 항목을 밀어 시험 전에 끝나지 않는다.
public struct ExamPlanBasis: Codable, Sendable, Equatable, Hashable {
    public var period: ExamPlanPeriod
    public var notes: ExamPlanNotes
    public var examDay: LocalDate

    public init(period: ExamPlanPeriod, notes: ExamPlanNotes, examDay: LocalDate) {
        self.period = period
        self.notes = notes
        self.examDay = examDay
    }
}

extension CourseFile {
    // 범위가 있고 시험 날이 오지 않은 시험만 놓는다. 계획이 아직 없는 시험은 기준이 없으므로 놓는다.
    public func needsPlan(_ exam: Exam, proofs: Set<UUID>, today: LocalDate, settings: Settings, calendar: Calendar) -> Bool {
        guard !scope(of: exam).isEmpty, let start = exam.start else { return false }
        let examDay = settings.studyDay(of: start, calendar: calendar)
        guard examDay > today else { return false }
        guard let basis = exam.planBasis, let period = exam.planPeriod else { return true }
        return basis
            != ExamPlanBasis(
                period: period.fitted(before: examDay, from: basis.examDay), notes: planNotes(of: exam, proofs: proofs), examDay: examDay)
    }
}
