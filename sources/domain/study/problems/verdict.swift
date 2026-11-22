import Foundation

public enum Verdict: String, Codable, Sendable, CaseIterable {
    case correct, partial, wrong

    // 준비 점수에서 판정 하나의 값이다(#573).
    public var score: Double {
        switch self {
        case .correct: 1
        case .partial: 0.5
        case .wrong: 0
        }
    }

    public var isMistake: Bool { self != .correct }
}
