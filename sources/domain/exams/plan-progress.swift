import Foundation

// 계획의 줄과 단계는 했다, 안 했다가 아니라 한 양과 전체 양으로 센다. 정독은 넘긴 카드, 증명과 문제풀이는 채점된 문제, 어제 오답은
// 다시 맞힌 문제가 한 양이 된다. 끝났는지는 이 값에서만 읽는다.
public struct PlanProgress: Sendable, Equatable, Hashable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    // 전체가 없으면 끝낼 것이 정해지지 않은 것이라 끝난 것으로 보지 않는다.
    public var isDone: Bool { total > 0 && done >= total }
    public var isStarted: Bool { done > 0 }
    public var left: Int { max(total - done, 0) }
    public var fraction: Double { total > 0 ? min(max(Double(done) / Double(total), 0), 1) : 0 }
}
