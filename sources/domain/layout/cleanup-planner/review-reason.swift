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

extension ReviewReason {
    public var label: String {
        switch self {
        case .guessedWeek: String(localized: .reviewReasonGuessedWeek)
        case .unknownWeek: String(localized: .reviewReasonUnknownWeek)
        case .guessedNumber: String(localized: .reviewReasonGuessedNumber)
        case .unknownNumber: String(localized: .reviewReasonUnknownNumber)
        case .guessedExam: String(localized: .reviewReasonGuessedExam)
        case .guessedOrigin: String(localized: .reviewReasonGuessedOrigin)
        case .guessedFolder: String(localized: .reviewReasonGuessedFolder)
        case .unknownFile: String(localized: .reviewReasonUnknownFile)
        case .unknownFolder: String(localized: .reviewReasonUnknownFolder)
        case .nameCollision: String(localized: .reviewReasonNameCollision)
        }
    }
}
