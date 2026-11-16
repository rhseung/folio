import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct CleanupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup", abstract: String(localized: .cleanupAbstract),
        subcommands: subcommandTypes)

    static func link(_ m: PlannedMove) -> String {
        ((m.exam.map { [String(localized: .cleanupPlanLinkExam($0))] } ?? [])
            + (m.kind == .pastExam ? [String(localized: .cleanupPlanLinkPastExam)] : []))
            .joined(separator: ", ")
    }

}
