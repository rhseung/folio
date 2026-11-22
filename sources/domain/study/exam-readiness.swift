import FolioCore
import Foundation

// 시험 카드가 그리는 범위 단원의 셈이다(#575).
public struct ExamReadiness: Sendable, Equatable {
    public var units: Int
    public var ready: Int
    public var done: Int
    public var problemsSolved: Int
    public var problemsTotal: Int
    // 범위 단원 중 이은 문제가 최소 개수보다 적은 단원이다. 시험 카드가 문제 만들기를 권한다.
    public var fewProblems: [UUID]

    public var fraction: Double { units == 0 ? 0 : Double(ready) / Double(units) }
}

extension CourseStudy {
    public func readiness(for exam: Exam) -> ExamReadiness {
        let scope = file.scopeUnits(of: exam)
        let states = scope.map { (unit: $0, readiness: readiness(of: $0.id)) }
        let ids = Set(scope.map(\.id))
        let records = allProblems.filter { !ids.isDisjoint(with: $0.problem.unitIds) }
        return ExamReadiness(
            units: scope.count, ready: states.filter { $0.readiness.state == .ready }.count, done: scope.filter(\.isDone).count,
            problemsSolved: records.filter(\.solved).count, problemsTotal: records.count,
            fewProblems: states.filter { $0.readiness.state == .fewProblems }.map(\.unit.id))
    }

    // 범위가 정해진 다가오는 시험 중 가장 가까운 것이다. 단원 페이지는 이 시험을 기준으로 단원을 나눈다.
    public func nextExam(now: Date, calendar: Calendar) -> Exam? {
        file.exams
            .filter { !file.scope(of: $0).isEmpty && $0.start != nil && !$0.isOver(now: now, today: today, calendar: calendar) }
            .min { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    // 단원의 렉처 쪽마다 본 쪽인지다. 쪽 구간 여럿은 이어 붙인다.
    public func pageMarks(of unit: Unit) -> [Bool] {
        unit.lecturePages.flatMap { r in
            let seen = seenPages(of: r.materialId)
            return r.pages.map { seen.contains($0) }
        }
    }
}
