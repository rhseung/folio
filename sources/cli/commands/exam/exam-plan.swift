import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension ExamCommand {
    struct Plan: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .examPlanAbstract), subcommands: subcommandTypes)

    }
}
