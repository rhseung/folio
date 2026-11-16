import ArgumentParser
import FolioDomain
import Foundation

struct ReleaseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release", abstract: "Decide, tag and publish releases.", subcommands: [Next.self, Tag.self, Past.self])

    struct Next: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the next version if the PRs merged since the latest tag have patch notes; print nothing otherwise.")

        @Option(help: "The commit to release.")
        var at = "HEAD"

        func run() throws {
            let latest = try ReleaseTags.latest(at: at)
            let prs = try MergedPullRequests.between(latest.map(ReleaseTags.name), and: at)
            if let next = ReleasePlan.next(after: latest, prs: prs) { print(next) }
        }
    }

    struct Tag: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Tag a commit as v<version>, dated at the commit, and push the tag.")

        @Argument(help: "The version.")
        var version: String

        @Option(help: "The commit to tag.")
        var at = "HEAD"

        func run() throws {
            guard let v = PatchNotes.Version(version) else { throw DevError("\(version) is not X.Y.Z") }
            try ReleaseTags.create(v, at: at, push: true)
            print(ReleaseTags.name(v))
        }
    }

    // 버전을 PR마다 올리기 전에 머지된 PR을 나중에 버전으로 나눌 때 쓴다. 그 커밋의 코드 버전은 태그와 다르므로 앱을
    // 빌드하지 않고 노트만 게시한다.
    struct Past: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Tag a past commit as v<version> and publish a release with only its notes, dated at the commit.")

        @Argument(help: "The version.")
        var version: String

        @Argument(help: "The last commit of the version.")
        var commit: String

        @Flag(help: "Print the tag and the body without tagging or publishing.")
        var dryRun = false

        func run() throws {
            guard let v = PatchNotes.Version(version) else { throw DevError("\(version) is not X.Y.Z") }
            let sha = try Shell.run("git", "rev-parse", "--verify", "\(commit)^{commit}")
            if let later = try ReleaseTags.versions(at: sha).first(where: { $0 >= v }) {
                throw DevError("\(ReleaseTags.name(later)) is already at or before \(sha)")
            }
            let body = try ReleaseTags.body(for: v, at: sha, assets: false)
            if dryRun {
                print("\(ReleaseTags.name(v)) at \(sha), \(try ReleaseTags.date(of: sha).formatted(.iso8601))\n\n\(body)")
                return
            }
            try ReleaseTags.create(v, at: sha, push: true)
            let file = FileManager.default.temporaryDirectory.appending(path: "folio-\(v)-notes.md")
            try body.write(to: file, atomically: true, encoding: .utf8)
            try Shell.run(
                "gh", "release", "create", ReleaseTags.name(v), "--verify-tag", "--title", "Folio \(v)", "--notes-file", file.path())
            print("\(ReleaseTags.name(v)) published")
        }
    }
}
