import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct QuizCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quiz", abstract: String(localized: .quizAbstract),
        subcommands: subcommandTypes)
}
