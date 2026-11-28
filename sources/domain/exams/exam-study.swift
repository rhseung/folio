import FolioCore
import Foundation

// 시험 카드가 세는 범위의 공부다. "준비 1/4단원 · 다 함 2/4 · 범위 문제 22개 중 9개 풂"
public struct ExamStudy: Sendable, Equatable {
    public var units: [Unit]
    public var ready: Int
    public var done: Int
    public var problemsSolved: Int
    public var problemsTotal: Int
    public var fewProblems: [Unit]
    public var planDone: Int
    public var planTotal: Int
    // 못 하고 지났거나 미룬 계획 항목 수다.
    public var planLate: Int

    // 시험 화면의 순조로움이다. 계획은 날마다 다시 놓지 않으므로, 밀린 항목이 없으면 계획대로 가고 있는 것이다.
    public var onTrack: Bool { planLate == 0 }
}

extension CourseStudy {
    public func study(of exam: Exam) -> ExamStudy {
        let units = file.scopeUnits(of: exam)
        let ids = Set(units.map(\.id))
        let scoped = allProblems.filter { !ids.isDisjoint(with: $0.problem.unitIds) }
        let readiness = units.map { readiness(of: $0.id) }
        let items = exam.plan.filter { !$0.isRemoved }
        let due = items.filter { $0.day <= today }
        return ExamStudy(
            units: units, ready: readiness.filter { $0.state == .ready }.count, done: units.filter(\.isDone).count,
            problemsSolved: scoped.filter(\.solved).count, problemsTotal: scoped.count,
            fewProblems: zip(units, readiness).filter { $0.1.state == .fewProblems }.map(\.0),
            planDone: due.filter(isDone).count, planTotal: due.count,
            planLate: items.count { $0.lateFrom(today: today, done: isDone($0)) != nil })
    }
}
