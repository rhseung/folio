import ArgumentParser

struct ProposalCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "proposal", abstract: String(localized: .proposalAbstract), subcommands: subcommandTypes)
}
