import Foundation

public struct CleanupPlan: Codable, Sendable, Equatable {
    public var moves: [PlannedMove]
    public var skipped: [String]
    public var removals: [String]

    public init(moves: [PlannedMove], skipped: [String], removals: [String] = []) {
        self.moves = moves
        self.skipped = skipped
        self.removals = removals
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moves = try c.decode([PlannedMove].self, forKey: .moves)
        skipped = try c.decode([String].self, forKey: .skipped)
        removals = try c.decodeIfPresent([String].self, forKey: .removals) ?? []
    }
}

extension CleanupPlan {
    public var proposals: [Proposal] { moves.map(\.proposal) }

    // 검토 표시가 붙은 이동은 따로 허락해야 옮긴다. 출처가 불확실한 파일을 실수로 옮기지 않기 위해서다.
    public func approved(includeFlagged: Bool) -> [PlannedMove] {
        proposals.filter { includeFlagged || $0.flag == nil }.compactMap {
            if case .cleanup(let m) = $0.source { m } else { nil }
        }
    }
}
