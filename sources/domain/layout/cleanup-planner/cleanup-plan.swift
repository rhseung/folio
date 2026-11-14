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
