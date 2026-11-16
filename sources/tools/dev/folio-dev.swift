import ArgumentParser

@main
struct FolioDev: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folio-dev", abstract: "Folio's version, releases and release notes, for mise tasks and the release workflow.",
        subcommands: [VersionCommand.self, ReleaseCommand.self, ReleaseNotesCommand.self])
}
