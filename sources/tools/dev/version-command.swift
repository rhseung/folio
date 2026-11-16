import ArgumentParser
import FolioDomain
import Foundation

// 버전은 `FolioVersion.marketing` 한 곳에만 있다. 빌드 번호는 커밋 수라 파일에 두지 않는다(main은 스쿼시 머지만 받아
// 머지마다 하나씩 는다). 앱의 MARKETING_VERSION은 `mise run generate`가 Swift로 같은 상수를 읽어 쓴다.
struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version", abstract: "Read, raise or tag the version in FolioVersion.",
        subcommands: [Get.self, Bump.self, Tag.self])

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the version (X.Y.Z), at a commit if given.")

        @Option(help: "Read the version at this commit instead of the checkout.")
        var at: String?

        func run() throws { print(try version(at: at)) }
    }

    enum Part: String, ExpressibleByArgument, CaseIterable { case major, minor, patch }

    struct Bump: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Raise the version in FolioVersion and print it.")

        @Argument(help: "major, minor or patch")
        var part: Part

        func run() throws {
            guard let current = PatchNotes.Version(try version(at: nil)) else { throw DevError("the version is not X.Y.Z") }
            let next =
                switch part {
                case .major: PatchNotes.Version(current.major + 1, 0, 0)
                case .minor: PatchNotes.Version(current.major, current.minor + 1, 0)
                case .patch: PatchNotes.Version(current.major, current.minor, current.patch + 1)
                }
            guard let source = VersionLiteral.replacing(try VersionLiteral.file(), with: next.description) else {
                throw DevError("no FolioVersion.marketing in \(VersionLiteral.path)")
            }
            try source.write(to: URL(filePath: VersionLiteral.path), atomically: true, encoding: .utf8)
            print(next)
        }
    }

    struct Tag: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Tag origin/main as v<version> and push the tag, which drafts its GitHub release.")

        // 로컬 체크아웃에는 머지하지 않은 작업이 있을 수 있으므로, 태그는 origin/main에 단다.
        func run() throws {
            try Shell.run("git", "fetch", "-q", "origin", "main", "--tags")
            let version = try version(at: "origin/main")
            let tag = "v\(version)"
            if (try? Shell.run("git", "rev-parse", "-q", "--verify", "refs/tags/\(tag)")) != nil {
                throw DevError("\(tag) already exists; raise the version first (mise run version-bump -- patch)")
            }
            try Shell.run("git", "tag", "-a", tag, "origin/main", "-m", "Folio \(version)")
            try Shell.run("git", "push", "origin", tag)
            print("\(tag) pushed; the release workflow drafts its release")
        }
    }

    static func version(at commit: String?) throws -> String {
        let source = try commit.map { try Shell.run("git", "show", "\($0):\(VersionLiteral.path)") } ?? VersionLiteral.file()
        guard let version = VersionLiteral.read(source), PatchNotes.Version(version) != nil else {
            throw DevError("no X.Y.Z FolioVersion.marketing in \(VersionLiteral.path)\(commit.map { " at \($0)" } ?? "")")
        }
        return version
    }
}
