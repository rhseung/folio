import Foundation

public enum ReviewResult: String, Codable, Sendable, CaseIterable {
    case again, hard, good, easy
    case skip
}
