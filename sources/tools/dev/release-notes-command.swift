import ArgumentParser
import FolioDomain

// 머지한 뒤에 고친 본문도 반영되도록, 커밋 메시지가 아니라 PR 본문을 릴리스할 때 읽는다. 앱은 같은 본문을
// `PatchNotes`로 다시 읽는다.
struct ReleaseNotesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release-notes", abstract: "Write a GitHub release's body from the PRs merged to main.",
        subcommands: [Body.self, Preview.self])

    struct Body: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "The body for the PRs merged after <since> up to <until>.")

        @Argument(help: "The previous release's ref; empty for the first release.")
        var since: String

        @Argument(help: "The last commit of the release.")
        var until = "HEAD"

        func run() throws { try ReleaseNotesCommand.write(since: since.isEmpty ? nil : since, until: until) }
    }

    struct Preview: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "The next release's body, since the latest v* tag unless given.")

        @Argument(help: "The previous release's ref.")
        var since: String?

        func run() throws {
            let latest = try? Shell.run("git", "describe", "--tags", "--abbrev=0", "--match", "v*")
            try ReleaseNotesCommand.write(since: since ?? latest, until: "HEAD")
        }
    }

    static func write(since: String?, until: String) throws {
        print(PatchNotes.releaseBody(try MergedPullRequests.between(since, and: until), first: since == nil))
    }
}
