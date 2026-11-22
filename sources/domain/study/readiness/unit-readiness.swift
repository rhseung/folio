import FolioCore
import Foundation

public struct UnitReadiness: Sendable, Equatable {
    public var state: ReadinessState
    public var score: Double?
    public var problems: Int
    public var judged: Int
    public var wrong: Int
    public var recheck: Int
    // 족보 묶음에서 이 단원에 이은 문제 수다. 계획의 무게로 쓴다.
    public var pastExam: Int
    // 개념 모름으로 틀린 문제의 렉처 쪽이다.
    public var conceptPages: [ProblemPage]

    public init(
        state: ReadinessState, score: Double?, problems: Int = 0, judged: Int = 0, wrong: Int = 0, recheck: Int = 0, pastExam: Int = 0,
        conceptPages: [ProblemPage] = []
    ) {
        self.state = state
        self.score = score
        self.problems = problems
        self.judged = judged
        self.wrong = wrong
        self.recheck = recheck
        self.pastExam = pastExam
        self.conceptPages = conceptPages
    }

    // 계획이 날을 나누는 무게다. 준비 안 된 정도, 출제 빈도, 문제 부족을 더한다. 준비된 단원도 한 번은 들어가도록
    // 바닥을 둔다.
    public var planWeight: Double {
        let gap = 1 - (score ?? 0)
        let frequency = min(Double(pastExam), 6) / 6
        let few = state == .fewProblems ? 0.5 : 0
        return max(0.2, gap + 0.5 * frequency + few)
    }
}
