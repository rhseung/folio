import Foundation

public enum ProblemSource: String, Codable, Sendable, CaseIterable {
    case pastExam = "past_exam"
    case textbook
    case exercise
    case assignment
    case claude
}
