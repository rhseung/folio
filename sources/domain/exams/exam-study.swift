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

    // 시험 화면의 순조로움이다. 범위 단원의 준비와 계획 진행으로 본다.
    public var onTrack: Bool {
        guard !units.isEmpty else { return true }
        let readyShare = Double(ready) / Double(units.count)
        let planShare = planTotal == 0 ? readyShare : Double(planDone) / Double(planTotal)
        return readyShare >= 0.5 || planShare >= 0.5
    }
}

extension CourseStudy {
    public func study(of exam: Exam) -> ExamStudy {
        let units = UnitTree.outline(file.units).map(\.unit).filter { exam.scopeUnitIds.contains($0.id) }
        let ids = Set(units.map(\.id))
        let scoped = allProblems.filter { !ids.isDisjoint(with: $0.problem.unitIds) }
        let readiness = units.map { readiness(of: $0.id) }
        let items = exam.plan.filter { !$0.isRemoved && $0.day <= today }
        return ExamStudy(
            units: units, ready: readiness.filter { $0.state == .ready }.count, done: units.filter(\.isDone).count,
            problemsSolved: scoped.filter(\.solved).count, problemsTotal: scoped.count,
            fewProblems: zip(units, readiness).filter { $0.1.state == .fewProblems }.map(\.0),
            planDone: items.filter { isDone($0, in: exam) }.count, planTotal: items.count)
    }
}
