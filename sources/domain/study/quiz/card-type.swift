import Foundation

public enum CardType: String, Codable, Sendable, CaseIterable {
    case free, trueFalse = "true_false", choice, fill, proof, handwritten
}
