import FolioCore
import Foundation

// 단원을 아는지 문제 판정으로 잰다(#573 "단원의 준비"). 진척은 투입량이고 다 함은 자기 평가라서 따로 둔다.
public enum Readiness {
    public struct Item: Sendable, Equatable {
        // 마지막 판정이다. 안 푼 문제는 nil이다.
        public var verdict: Verdict?
        public var basis: GradeBasis?
        public var status: WrongStatus

        public init(verdict: Verdict?, basis: GradeBasis? = nil, status: WrongStatus = .untried) {
            self.verdict = verdict
            self.basis = basis
            self.status = status
        }

        public var weight: Double { basis?.weight ?? 1 }
    }

    // 안 푼 문제도 점수 0으로 분모에 든다. 그래야 쉬운 문제 몇 개만 풀어 준비됨이 되지 않는다.
    public static func score(_ items: [Item]) -> Double? {
        guard items.contains(where: { $0.verdict != nil }) else { return nil }
        let total = items.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        return items.reduce(0) { $0 + $1.weight * ($1.verdict?.score ?? 0) } / total
    }

    public static func state(_ items: [Item], readyScore: Double, minProblems: Int) -> ReadinessState {
        if items.count < minProblems { return .fewProblems }
        guard let score = score(items) else { return .noVerdict }
        let clean = !items.contains { $0.status.needsWork }
        return score >= readyScore && clean ? .ready : .weak
    }
}
