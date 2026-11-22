import FolioCore
import FolioDomain
import Foundation

public struct GradeOutcome: Sendable, Equatable {
    public var grade: ProblemGrade
    public var basis: GradeBasis

    public init(grade: ProblemGrade, basis: GradeBasis) {
        self.grade = grade
        self.basis = basis
    }
}

extension ClaudeClient {
    // 채점 근거는 정답, 해설, Claude 풀이 순이다(#576). 정답이 있는 형식은 Claude를 부르지 않고, 단답이 글자로만 다르면
    // 같은 답인지만 묻는다.
    public func grade(_ problem: Problem, answer: String, answerImages: [Data] = []) async throws -> GradeOutcome {
        if answerImages.isEmpty, let verdict = problem.keyVerdict(for: answer) {
            return GradeOutcome(grade: ProblemGrade(verdict: verdict), basis: .key)
        }
        if answerImages.isEmpty, problem.format == .short, problem.hasKey, let key = problem.answer {
            let same = try await sameAnswer(answer, key: key, problem: problem.text)
            return GradeOutcome(grade: ProblemGrade(verdict: same ? .correct : .wrong), basis: .key)
        }
        let grade = try await gradeProblem(problem, answer: answer.isEmpty ? nil : answer, answerImages: answerImages)
        return GradeOutcome(grade: grade, basis: problem.hasSolution || problem.hasKey ? .solution : .claude)
    }
}
