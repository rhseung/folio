import ArgumentParser

struct ImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import", abstract: String(localized: .importAbstract),
        discussion: String(localized: .importDiscussion),
        subcommands: GeneratedCommands.`import`)
}
