import FolioCore
import Foundation

// 사용자가 풀이의 판정이나 이유를 바꾼 기록이다. 바꾼 것이 최종이고, 날짜는 원래 풀이의 공부일로 센다.
public struct ProblemVerdictEvent: LogEvent, Equatable {
    public static let type = "problem_verdict"
    public var attemptId: UUID
    public var verdict: Verdict
    public var reason: WrongReason?

    public init(attemptId: UUID, verdict: Verdict, reason: WrongReason? = nil) {
        self.attemptId = attemptId
        self.verdict = verdict
        self.reason = reason
    }
}
