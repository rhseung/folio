import FolioCore
import Foundation

// 계획의 줄에서 바로 여는 풀기다. 줄마다 어떤 문제를 어떤 방식으로 푸는지는 여기서만 정한다.
public struct PlanSolve: Sendable, Equatable {
    public var problems: [UUID]
    public var mode: SolveMode
    public var shuffled: Bool
    public var minutes: Int?

    public init(problems: [UUID], mode: SolveMode = .typing, shuffled: Bool = false, minutes: Int? = nil) {
        self.problems = problems
        self.mode = mode
        self.shuffled = shuffled
        self.minutes = minutes
    }
}

extension CourseStudy {
    // 시험 정보에 시작과 끝이 있으면 그 시간이 모의고사의 제한 시간이고, 없으면 설정의 기본값이다.
    public func mockMinutes(for exam: Exam?) -> Int {
        if let start = exam?.start, let end = exam?.end, end > start { return max(1, Int((end.timeIntervalSince(start) / 60).rounded())) }
        return max(1, settings.mockMinutes)
    }

    public func scopeProblems(of exam: Exam) -> [ProblemRecord] {
        let scope = Set(file.scope(of: exam))
        return allProblems.filter { !scope.isDisjoint(with: $0.problem.unitIds) }
    }

    // 모의고사 줄과 어제 오답 줄만 풀기를 연다. 풀 문제가 없으면 nil이다.
    public func solve(_ row: PlanRow, seed: UInt64) -> PlanSolve? {
        switch row.kind {
        case .wrong:
            let wrong = allProblems.filter(\.status.needsWork)
            return wrong.isEmpty
                ? nil : PlanSolve(problems: wrong.map(\.problem.id), mode: .fitting(nil, formats: wrong.map(\.problem.format)))
        case .mock:
            guard let exam = file.exams.first(where: { $0.id == row.examId }) else { return nil }
            let ids = mockProblems(for: exam, seed: seed)
            return ids.isEmpty ? nil : PlanSolve(problems: ids, mode: .mock, shuffled: true, minutes: mockMinutes(for: exam))
        case .makeNote, .note, .custom:
            return nil
        }
    }

    // 한 벌은 범위에 걸친 족보 묶음 하나다. 덜 푼 묶음을 먼저 고르고, 같으면 먼저 들어온 묶음이다. 범위에 족보가 없으면
    // 범위 문제를 섞어 과목의 족보 한 벌만큼 묶는다. 과목에 족보가 하나도 없으면 길이를 알 수 없으므로 범위 문제를 모두 푼다.
    func mockProblems(for exam: Exam, seed: UInt64) -> [UUID] {
        let scope = Set(file.scope(of: exam))
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
