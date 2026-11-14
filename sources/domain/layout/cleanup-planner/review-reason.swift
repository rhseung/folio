import Foundation

public enum ReviewReason: String, Codable, Sendable, CaseIterable {
    case guessedWeek
    case unknownWeek
    case guessedNumber
    case unknownNumber
    case guessedExam
    case guessedOrigin
    case guessedFolder
    case unknownFile
    case unknownFolder
    case nameCollision
}
