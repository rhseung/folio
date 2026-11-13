import ArgumentParser

/// Only the writes: reading the LMS takes the login the app keeps in iCloud Keychain, which a command line tool signed
/// without the app's team can't reach.
struct LMSCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lms", abstract: String(localized: .lmsAbstract), subcommands: GeneratedCommands.lms)
}
