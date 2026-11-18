import ArgumentParser
import FolioDomain

// 머지한 뒤에 고친 본문도 반영되도록, 커밋 메시지가 아니라 PR 본문을 릴리스할 때 읽는다. 앱은 같은 본문을
// `PatchNotes`로 다시 읽는다.
struct ReleaseNotesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release-notes", abstract: "Write a GitHub release's body from the PRs merged to main.",
        subcommands: [Body.self, Title.self, Preview.self])

    struct Body: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "The body of a version: the PRs merged after the previous version's tag up to <until>.")

        @Argument(help: "The version.")
        var version: String

        @Argument(help: "The last commit of the release.")
        var until = "HEAD"

        @Option(help: "The previous release's ref, instead of the tag of the version before.")
        var since: String?

        @Option(help: "The bundles this minor ends, as a JSON array of names.")
        var bundles = "[]"

        func run() throws {
            guard let v = PatchNotes.Version(version) else { throw DevError("\(version) is not X.Y.Z") }
            print(
                try ReleaseTags.body(
                    for: v, at: until, since: since.flatMap { $0.isEmpty ? nil : $0 }, bundles: try ReleaseCommand.names(bundles)))
        }
    }

    struct Title: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "The title of a version's release, with the bundles it ends.")

        @Argument(help: "The version.")
        var version: String

        @Option(help: "The bundles this minor ends, as a JSON array of names.")
        var bundles = "[]"

        func run() throws {
            guard let v = PatchNotes.Version(version) else { throw DevError("\(version) is not X.Y.Z") }
            print(ReleaseTags.title(v, bundles: try ReleaseCommand.names(bundles)))
        }
    }

    struct Preview: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "The next releases and their bodies: one for each PR with patch notes since the latest tag.")

        func run() throws {
            let latest = try ReleaseTags.latest(at: "HEAD")
            let prs = try MergedPullRequests.between(latest.map(ReleaseTags.name), and: "HEAD")
            let bundles = try ReleaseBundles.all()
            let steps = ReleasePlan.steps(after: latest, prs: prs, bundles: bundles, released: try ReleaseTags.releasedBundles())
            guard !steps.isEmpty else {
                print("No PR since \(latest.map(ReleaseTags.name) ?? "the start") has patch notes; nothing to release.")
                return
            }
            var since = latest.map(ReleaseTags.name)
            for step in steps {
                let body = try ReleaseTags.body(for: step.version, at: step.commit, since: since, bundles: step.bundles)
                print("# \(ReleaseTags.title(step.version, bundles: step.bundles)) at \(step.commit.prefix(8))\n\n\(body)\n")
                since = step.commit
            }
        }
    }
}
