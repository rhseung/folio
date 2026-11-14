import Foundation

public enum Verdict: String, Codable, Sendable, CaseIterable {
    case correct, partial, wrong
}
