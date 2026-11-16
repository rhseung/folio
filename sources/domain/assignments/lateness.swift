import Foundation

// 마감 뒤의 과제가 얼마나 늦었고 몇 점까지 받을 수 있는지다. 낸 과제는 제출 시각으로, 아직 내지 않은 과제는 지금 낸다고 보고 센다.
public struct Lateness: Sendable, Equatable {
    public var days: Int
    // 지각 규칙이 있으면 받을 수 있는 최대 점수의 비율(0...1)이다.
    public var ceiling: Double?
    // 아직 내지 않은 과제에서 감점이 한 단계 더 커지는 시각이다.
    public var nextDrop: Date?

    public init(days: Int, ceiling: Double?, nextDrop: Date? = nil) {
        self.days = days
        self.ceiling = ceiling
        self.nextDrop = nextDrop
    }
}

extension CourseFile {
    public func lateRule(of a: Assignment) -> LateRule? { a.lateRule ?? policy.lateRule }

    public func lateness(of a: Assignment, at now: Date) -> Lateness? {
        guard let due = a.due else { return nil }
        let when: Date
        switch a.status {
        case .todo, .doing: when = now
        case .submitted, .graded:
            guard let submitted = a.submittedAt else { return nil }
            when = submitted
        case .missed: return nil
        }
        let days = LateRule.lateDays(due: due, at: when)
        guard days > 0 else { return nil }
        // 점수를 기록한 과제는 그 점수가 감점까지 들어간 최종 점수라 상한을 두지 않는다(사용자, 2026-11-15).
        let rule = scores.contains { $0.assignmentId == a.id } ? nil : lateRule(of: a)
        return Lateness(
            days: days, ceiling: rule?.ceiling(lateDays: days), nextDrop: a.status.isOpen ? rule?.nextDrop(due: due, at: now) : nil)
    }

    // 마감이 지났는데 아직 할 일로 남은 과제다. 마감이 이른 것부터 놓는다.
    public func overdueAssignments(at now: Date) -> [Assignment] {
        assignments.filter { $0.isOverdue(at: now) }.sorted { ($0.due ?? .distantPast, $0.title) < ($1.due ?? .distantPast, $1.title) }
    }
}

extension CourseFile {
    // 기록한 점수는 감점이 이미 들어간 최종 점수로 보고 그대로 센다. 한 번 더 깎으면 감점이 두 번 들어간다. 지각 규칙은 점수가
    // 아직 없는 지각 과제에만 쓰고(`lateness`), 그 과제가 받을 수 있는 최대 비율을 예상 점수의 상한으로 둔다.
    public func lateCeilings(at now: Date) -> [UUID: [Double]] {
        assignments.reduce(into: [:]) { caps, a in
            guard let component = a.componentId else { return }
            // 못 냄은 내지 않기로 한 과제라 점수를 적기 전까지 0점으로 센다. 빼면 못 냄을 눌렀을 때 예상 점수가 오른다.
            let missed = a.status == .missed && !scores.contains { $0.assignmentId == a.id }
            guard let ceiling = missed ? 0 : lateness(of: a, at: now)?.ceiling else { return }
            caps[component, default: []].append(ceiling)
        }
    }

    public func courseScore(at now: Date) -> GradeCalculator.CourseScore {
        GradeCalculator.score(components: components, entries: scores, ceilings: lateCeilings(at: now))
    }
}
