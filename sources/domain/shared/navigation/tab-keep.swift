import Foundation

public enum TabKeep {
    public struct Policy: Equatable, Sendable {
        public var limit: Int
        public var idle: TimeInterval

        public init(limit: Int, idle: TimeInterval) {
            self.limit = limit
            self.idle = idle
        }
    }

    // 녹음을 재생하는 탭을 버리면 듣던 것이 멈추므로, 재생 중인 탭은 시간이나 메모리 압박과 상관없이 남기고 다른
    // 탭이 나눠 쓰는 `limit`에도 세지 않는다.
    public static func alive<ID: Hashable>(
        selected: ID, alive: Set<ID>, left: [ID: Date], now: Date, policy: Policy,
        pressure: Bool = false, playing: Set<ID> = []
    ) -> Set<ID> {
        let playing = playing.intersection(alive).union([selected])
        guard !pressure else { return playing }
        let behind = alive.subtracting(playing)
            .map { (id: $0, left: left[$0] ?? now) }
            .filter { now.timeIntervalSince($0.left) < policy.idle }
            .sorted { $0.left > $1.left }
            .prefix(max(0, policy.limit))
        return Set(behind.map(\.id)).union(playing)
    }
}
