import Foundation

public enum WrongReason: String, Codable, Sendable, CaseIterable {
    case concept
    case method
    case calculation
    case misread
    // 모의시험에서만 고른다.
    case time

    public static func choices(mock: Bool) -> [WrongReason] { mock ? allCases : allCases.filter { $0 != .time } }
}
