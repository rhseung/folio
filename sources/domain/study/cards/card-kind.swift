import Foundation

public enum CardKind: String, Codable, Sendable, CaseIterable {
    case flip
    case trueFalse = "true_false"
}
