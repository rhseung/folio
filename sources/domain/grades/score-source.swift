import Foundation

public enum ScoreSource: Hashable, Sendable {
    case none, assignment(UUID), exam(UUID)
}
