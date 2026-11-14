import ArgumentParser

struct LMSCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lms", abstract: String(localized: .lmsAbstract), subcommands: GeneratedCommands.lms)
}
