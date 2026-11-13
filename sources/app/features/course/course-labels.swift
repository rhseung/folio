import FolioDomain
import Foundation

extension ReviewReason {
    var label: String {
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

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension MaterialRole {
    var label: String {
        switch self {
        case .syllabus: String(localized: .materialRoleSyllabus)
        case .lecture: String(localized: .materialRoleLecture)
        case .exercise: String(localized: .materialRoleExercise)
        case .textbook: String(localized: .materialRoleTextbook)
        case .assignment: String(localized: .materialRoleAssignment)
        case .lab: String(localized: .materialRoleLab)
        case .inherited: String(localized: .materialRoleInherited)
        case .exam: String(localized: .materialRoleExam)
        case .study: String(localized: .materialRoleStudy)
        case .archive: String(localized: .materialRoleArchive)
        case .other: String(localized: .materialRoleOther)
        }
    }
}

/// The names of what a past class still lacks, for the sessions notice and Today's wrap-up card.
extension WrapUpItem {
    var label: String {
        switch self {
        case .progress: String(localized: .wrapUpProgress)
        case .units: String(localized: .wrapUpUnits)
        case .note: String(localized: .wrapUpNote)
        case .attendance: String(localized: .wrapUpAttendance)
        }
    }
}
