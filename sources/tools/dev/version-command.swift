import ArgumentParser
import FolioDomain
import Foundation

// 버전의 원본은 `v<X.Y.Z>` 태그이고(`ReleaseTags`), 커밋한 `FolioVersion.marketing`은 개발 빌드의 자리표시값이다.
// 릴리스 빌드(release.yml, install-release)만 빌드하기 전에 태그의 버전을 써넣고 커밋하지 않는다. 빌드 번호는 커밋 수다.
struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Read the version from the release tags, write it into a release build, or tag a release by hand.",
        subcommands: [Get.self, Stamp.self, Tag.self])

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the latest release tag's version (X.Y.Z) at a commit, 0.0.0 if none.")

        @Option(help: "Read the tags merged into this commit instead of HEAD.")
        var at = "HEAD"

        func run() throws { print(try ReleaseTags.latest(at: at) ?? PatchNotes.Version(0, 0, 0)) }
    }

    struct Stamp: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Write a version into FolioVersion for a release build. Never commit the result.")

        @Argument(help: "The version; the latest release tag at HEAD if not given.")
        var version: String?

        func run() throws {
            let text = try version ?? (ReleaseTags.latest(at: "HEAD") ?? PatchNotes.Version(0, 0, 0)).description
            guard let next = PatchNotes.Version(text) else { throw DevError("\(text) is not X.Y.Z") }
            guard let source = VersionLiteral.replacing(try VersionLiteral.file(), with: next.description) else {
                throw DevError("no FolioVersion.marketing in \(VersionLiteral.path)")
            }
            try source.write(to: URL(filePath: VersionLiteral.path), atomically: true, encoding: .utf8)
            print(next)
        }
    }

    enum Part: String, ExpressibleByArgument, CaseIterable { case major, minor, patch }

    struct Tag: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Tag origin/main as the next major, minor or patch and push it, which builds and publishes its release.")

        @Argument(help: "major, minor or patch")
        var part: Part

        // 로컬 체크아웃에는 머지하지 않은 작업이 있을 수 있으므로, 태그는 origin/main에 단다.
        func run() throws {
            try Shell.run("git", "fetch", "-q", "origin", "main", "--tags")
            let latest = try ReleaseTags.latest(at: "origin/main") ?? PatchNotes.Version(0, 0, 0)
            let next =
                switch part {
                case .major: PatchNotes.Version(latest.major + 1, 0, 0)
                case .minor: PatchNotes.Version(latest.major, latest.minor + 1, 0)
                case .patch: PatchNotes.Version(latest.major, latest.minor, latest.patch + 1)
                }
            try ReleaseTags.create(next, at: "origin/main", push: true)
            print("\(ReleaseTags.name(next)) pushed; the release workflow builds and publishes it")
        }
    }
}
