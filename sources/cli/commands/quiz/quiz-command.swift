import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct QuizCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quiz", abstract: String(localized: .quizAbstract),
        subcommands: [List.self] + GeneratedCommands.quiz + [Record.self])
}
