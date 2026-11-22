import Foundation

public enum ProblemFormat: String, Codable, Sendable, CaseIterable {
    case trueFalse = "true_false"
    case choice
    case short
    case written

    // 정답이 있으면 앱이 바로 맞힌다. 서술은 언제나 Claude가 채점한다.
    public var gradesByKey: Bool { self != .written }
}
