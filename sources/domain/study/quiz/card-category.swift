import Foundation

public enum CardCategory: String, Codable, Sendable, CaseIterable {
    case definition, theorem, proof, counterexample, computation, concept, design
}
