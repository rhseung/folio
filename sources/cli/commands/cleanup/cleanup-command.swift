import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct CleanupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup", abstract: String(localized: .cleanupAbstract),
        subcommands: subcommandTypes)

    static let reasonText: [ReviewReason: String] = [
        .guessedWeek: String(localized: .cleanupReasonGuessedWeek),
        .unknownWeek: String(localized: .cleanupReasonUnknownWeek),
        .guessedNumber: String(localized: .cleanupReasonGuessedNumber),
        .unknownNumber: String(localized: .cleanupReasonUnknownNumber),
        .guessedExam: String(localized: .cleanupReasonGuessedExam),
        .guessedOrigin: String(localized: .cleanupReasonGuessedOrigin),
        .guessedFolder: String(localized: .cleanupReasonGuessedFolder),
        .unknownFile: String(localized: .cleanupReasonUnknownFile),
        .unknownFolder: String(localized: .cleanupReasonUnknownFolder),
        .nameCollision: String(localized: .cleanupReasonNameCollision),
    ]

    static func link(_ m: PlannedMove) -> String {
        ((m.exam.map { [String(localized: .cleanupPlanLinkExam($0))] } ?? [])
            + (m.kind == .pastExam ? [String(localized: .cleanupPlanLinkPastExam)] : []))
            .joined(separator: ", ")
    }

}
