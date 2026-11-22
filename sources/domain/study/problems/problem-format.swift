import Foundation

public enum ProblemFormat: String, Codable, Sendable, CaseIterable {
    case trueFalse = "true_false"
    case choice
    case short
    case written

    // 정답이 있으면 앱이 바로 맞힌다. 서술은 언제나 Claude가 채점한다.
    public var gradesByKey: Bool { self != .written }

    // 화면에서 바로 푸는 형식이다. 서술형은 문제집 PDF로 손으로 푼다(#577).
    public var onScreen: Bool { self != .written }
}
