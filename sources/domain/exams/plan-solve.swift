import FolioCore
import Foundation

// 계획 항목에서 바로 여는 풀기다(#576, #577, #578). 항목마다 어떤 문제를 어떤 방식으로 푸는지는 여기서만 정한다.
public struct PlanSolve: Sendable, Equatable {
    public var problems: [UUID]
    public var mode: SolveMode
    public var shuffled: Bool
    public var minutes: Int?
    // 오답 항목에 남은 오답 문제는 없고 모른 카드만 있으면 카드를 넘긴다. 넘기는 덱은 시험 범위 단원의 카드다.
    public var cardScope: [UUID]?
    public var cards: Bool { cardScope != nil }

    public init(problems: [UUID], mode: SolveMode = .typing, shuffled: Bool = false, minutes: Int? = nil, cardScope: [UUID]? = nil) {
        self.problems = problems
        self.mode = mode
        self.shuffled = shuffled
        self.minutes = minutes
        self.cardScope = cardScope
    }
}

extension CourseStudy {
    // 시험 정보에 시작과 끝이 있으면 그 시간이 모의시험의 제한 시간이고, 없으면 설정의 기본값이다.
    public func mockMinutes(for exam: Exam?) -> Int {
        if let start = exam?.start, let end = exam?.end, end > start { return max(1, Int((end.timeIntervalSince(start) / 60).rounded())) }
        return max(1, settings.mockMinutes)
    }

    public func scopeProblems(of exam: Exam) -> [ProblemRecord] {
        let scope = Set(exam.scopeUnitIds)
        return allProblems.filter { !scope.isDisjoint(with: $0.problem.unitIds) }
    }

    // 단원 항목과 사용자가 쓴 할 일은 풀기가 아니므로 nil이다. 풀 문제가 없어도 nil이다.
    public func solve(_ item: ExamPlanItem, in exam: Exam, seed: UInt64) -> PlanSolve? {
        switch item.target.kind {
        case .unit, .custom:
            return nil
        case .problems:
            let records = item.target.problemIds.map { $0.compactMap { problems[$0] } } ?? item.target.id.map(problems(inSet:)) ?? []
            return records.isEmpty ? nil : PlanSolve(problems: records.map(\.problem.id))
        case .mixed:
            var rng = SeededGenerator(seed: seed)
            let ids = scopeProblems(of: exam).map(\.problem.id).shuffled(using: &rng)
            return ids.isEmpty ? nil : PlanSolve(problems: ids, shuffled: true)
        case .mock:
            let ids = mockProblems(for: exam, seed: seed)
            return ids.isEmpty ? nil : PlanSolve(problems: ids, mode: .mock, shuffled: true, minutes: mockMinutes(for: exam))
        case .wrong:
            let wrong = scopeProblems(of: exam).filter(\.status.needsWork).map(\.problem.id)
            if !wrong.isEmpty { return PlanSolve(problems: wrong) }
            let scope = Set(exam.scopeUnitIds)
            return allCards.contains { $0.status.needsWork && scope.contains($0.card.unitId) }
                ? PlanSolve(problems: [], cardScope: exam.scopeUnitIds) : nil
        }
    }

    // 한 벌은 범위에 걸친 족보 묶음 하나다. 덜 푼 묶음을 먼저 고르고, 같으면 먼저 들어온 묶음이다. 범위에 족보가 없으면
    // 범위 문제를 섞어 과목의 족보 한 벌만큼 묶는다. 과목에 족보가 하나도 없으면 길이를 알 수 없으므로 범위 문제를 모두 푼다.
    func mockProblems(for exam: Exam, seed: UInt64) -> [UUID] {
        let scope = Set(exam.scopeUnitIds)
        let pastSets = file.problemSets.filter { $0.source == .pastExam && !$0.problems.isEmpty }
        let inScope = pastSets.filter { set in set.problems.contains { !scope.isDisjoint(with: $0.unitIds) } }
        let solved = { (set: ProblemSet) in problems(inSet: set.id).filter(\.solved).count }
        if let set = inScope.enumerated().min(by: { (solved($0.element), $0.offset) < (solved($1.element), $1.offset) })?.element {
            return set.problems.map(\.id)
        }
        var rng = SeededGenerator(seed: seed)
        let mixed = scopeProblems(of: exam).map(\.problem.id).shuffled(using: &rng)
        guard let length = pastSets.map(\.problems.count).max() else { return mixed }
        return Array(mixed.prefix(length))
    }
}
