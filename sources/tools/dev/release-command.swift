import ArgumentParser
import FolioDomain
import Foundation

private struct MatrixRow: Encodable {
    var version: String
    var ref: String
    var bundles: [String]
}

private struct Matrix: Encodable { var include: [MatrixRow] }

private struct RenumberMark {
    var version: PatchNotes.Version
    var pr: Int
    var commit: String
    var notesOnly: Bool
}

struct ReleaseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release", abstract: "Decide, tag and publish releases.", subcommands: [Plan.self, Tag.self, Past.self, Renumber.self])

    struct Plan: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract:
                "Print the releases to build at a commit as a GitHub Actions matrix: tags not yet published, then one version for each PR with patch notes since the latest tag."
        )

        @Option(help: "The commit to release.")
        var at = "HEAD"

        @Option(help: "Append the planned versions and the bundles still open to this Markdown file (the step summary).")
        var summary: String?

        func run() throws {
            let tags = try ReleaseTags.versions(at: at)
            let latest = tags.max()
            let prs = try MergedPullRequests.between(latest.map(ReleaseTags.name), and: at)
            let bundles = try ReleaseBundles.all()
            let released = try ReleaseTags.releasedBundles()
            let pending = ReleasePlan.pending(tags: tags, published: try ReleaseTags.published())
            let steps = ReleasePlan.steps(after: latest, prs: prs, bundles: bundles, released: released)
            // 이미 단 태그는 그 태그의 커밋을, 새 버전은 그 버전을 낸 PR의 머지 커밋을 빌드한다.
            let rows =
                try pending.map { MatrixRow(version: $0.description, ref: ReleaseTags.name($0), bundles: try ReleaseTags.bundles(of: $0)) }
                + steps.map { MatrixRow(version: $0.version.description, ref: $0.commit, bundles: $0.bundles) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            print(String(bytes: try encoder.encode(Matrix(include: rows)), encoding: .utf8) ?? "")
            guard let summary else { return }
            let text = ReleaseCommand.table(pending: pending, steps: steps) + "\n" + ReleasePlan.summary(bundles, released: released)
            let handle = try FileHandle(forWritingTo: URL(filePath: summary))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        }
    }

    static func table(pending: [PatchNotes.Version], steps: [ReleasePlan.Step], title: String = "릴리스") -> String {
        guard !pending.isEmpty || !steps.isEmpty else { return "## \(title)\n낼 버전이 없습니다.\n" }
        let rows =
            pending.map { "| \($0) | 게시되지 않은 태그 | |" }
            + steps.map { step in
                "| \(step.version) | " + step.prs.map { "#\($0)" }.joined(separator: " ") + " | "
                    + step.bundles.joined(separator: ", ") + " |"
            }
        return "## \(title)\n| 버전 | PR | 묶음 |\n| --- | --- | --- |\n" + rows.joined(separator: "\n") + "\n"
    }

    static func names(_ json: String) throws -> [String] {
        guard !json.isEmpty else { return [] }
        return try JSONDecoder().decode([String].self, from: Data(json.utf8))
    }

    struct Tag: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Tag a commit as v<version>, dated at the commit, and push the tag.")

        @Argument(help: "The version.")
        var version: String

        @Option(help: "The commit to tag.")
        var at = "HEAD"

        @Option(help: "The bundles this minor ends, as a JSON array of names, kept in the tag's message.")
        var bundles = "[]"

        // 다시 돌린 실행이 앞 실행이 단 태그에서 멈추지 않도록, 같은 커밋의 같은 태그는 그대로 둔다.
        func run() throws {
            guard let v = PatchNotes.Version(version) else { throw DevError("\(version) is not X.Y.Z") }
            if ReleaseTags.exists(v) {
                let tagged = try Shell.run("git", "rev-parse", "--verify", "\(ReleaseTags.name(v))^{commit}")
                guard tagged == (try Shell.run("git", "rev-parse", "--verify", "\(at)^{commit}")) else {
                    throw DevError("\(ReleaseTags.name(v)) is already on another commit")
                }
            } else {
                try ReleaseTags.create(v, at: at, bundles: try ReleaseCommand.names(bundles), push: true)
            }
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
            try ReleaseTags.publish(v, body: body)
            print("\(ReleaseTags.name(v)) published")
        }
    }

    // 자동 릴리스가 지난 PR 나누기보다 먼저 돌아 한 버전에 PR 80여 개를 담은 일(#557)을 바로잡을 때 쓴다. 지울 태그를 지우고,
    // 노트만 있는 지난 버전과 빌드할 버전을 PR의 머지 커밋에 단 뒤 release.yml을 돌린다. 그 실행의 plan이 빌드할 버전을
    // 게시되지 않은 태그로 먼저 게시하고, 그 뒤 패치 노트가 있는 PR마다 버전을 하나씩 낸다.
    struct Renumber: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract:
                "Delete a range of release tags with their releases, tag notes-only versions and a version to build at PRs' merge commits, then run the release workflow for the rest."
        )

        @Option(help: "Versions to delete with their releases: one version, or A-B for every tag from A to B.")
        var drop: [String] = []

        @Option(help: "A notes-only version at a PR's merge commit: <version>@<PR number>. Repeat in any order.")
        var past: [String] = []

        @Option(help: "The version release.yml builds at a PR's merge commit: <version>@<PR number>.")
        var build: String?

        @Flag(help: "Print what would be deleted, each new version's body and the versions after them, without changing anything.")
        var dryRun = false

        func run() throws {
            try Shell.run("git", "fetch", "-q", "--force", "origin", "main", "--tags")
            let tags = try ReleaseTags.all()
            let dropped = try drop.flatMap { try Self.range($0, among: tags) }.sorted()
            let published = try ReleaseTags.published()
            let marks = try
                (past.map { try Self.mark($0, notesOnly: true) } + [build].compactMap { $0 }.map { try Self.mark($0, notesOnly: false) })
                .sorted { $0.version < $1.version }
            guard let lastMark = marks.last else { throw DevError("give at least one --past or --build") }
            guard build == nil || !lastMark.notesOnly else {
                throw DevError("the version to build must be the highest one")
            }
            for (a, b) in zip(marks, marks.dropFirst())
            where (try? Shell.run("git", "merge-base", "--is-ancestor", a.commit, b.commit)) == nil {
                throw DevError("#\(a.pr) for \(a.version) is not merged before #\(b.pr) for \(b.version)")
            }
            let kept = tags.filter { !dropped.contains($0) }
            for mark in marks where kept.contains(mark.version) {
                let tagged = try Shell.run("git", "rev-parse", "--verify", "\(ReleaseTags.name(mark.version))^{commit}")
                guard tagged == mark.commit else { throw DevError("\(ReleaseTags.name(mark.version)) is already on another commit") }
            }

            var report = ["## 지울 버전"]
            report +=
                dropped.isEmpty
                ? ["없음"]
                : try dropped.map { v in
                    let sha = try Shell.run("git", "rev-parse", "--short", "\(ReleaseTags.name(v))^{commit}")
                    return "- \(ReleaseTags.name(v)) (\(sha), " + (published.contains(v) ? "릴리스와 태그" : "태그만") + ")"
                }
            var bodies: [PatchNotes.Version: String] = [:]
            var since: String?
            for mark in marks {
                let start =
                    try since
                    ?? ReleasePlan.previous(
                        before: mark.version, among: ReleaseTags.versions(at: mark.commit).filter { !dropped.contains($0) }
                    )
                    .map(ReleaseTags.name)
                let body = try ReleaseTags.body(for: mark.version, at: mark.commit, since: start, assets: !mark.notesOnly)
                bodies[mark.version] = body
                let date = try ReleaseTags.date(of: mark.commit).formatted(.iso8601)
                let kind = mark.notesOnly ? "노트만" : "release.yml이 빌드"
                report.append("\n## \(ReleaseTags.name(mark.version)): #\(mark.pr) (\(mark.commit.prefix(8)), \(date)), \(kind)\n\n\(body)")
                since = mark.commit
            }
            let after = try MergedPullRequests.between(lastMark.commit, and: "origin/main")
            let steps = ReleasePlan.steps(
                after: lastMark.version, prs: after, bundles: try ReleaseBundles.all(), released: try ReleaseTags.releasedBundles())
            report.append("\n" + ReleaseCommand.table(pending: [], steps: steps, title: "그 뒤 release.yml이 낼 버전"))
            print(report.joined(separator: "\n"))
            guard !dryRun else { return }

            for v in dropped { try ReleaseTags.delete(v, published: published.contains(v)) }
            for mark in marks {
                if !ReleaseTags.exists(mark.version) { try ReleaseTags.create(mark.version, at: mark.commit, push: true) }
                if mark.notesOnly, !published.contains(mark.version), let body = bodies[mark.version] {
                    try ReleaseTags.publish(mark.version, body: body)
                }
            }
            if build != nil { try Shell.run("gh", "workflow", "run", "release.yml", "--ref", "main") }
            print("\nDone. release.yml builds the rest; follow it with gh run watch.")
        }

        private static func mark(_ text: String, notesOnly: Bool) throws -> RenumberMark {
            let parts = text.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2, let version = PatchNotes.Version(parts[0]), let pr = Int(parts[1].trimmingPrefix("#")) else {
                throw DevError("\(text) is not <version>@<PR number>")
            }
            return RenumberMark(version: version, pr: pr, commit: try MergedPullRequests.mergeCommit(of: pr), notesOnly: notesOnly)
        }

        static func range(_ text: String, among tags: [PatchNotes.Version]) throws -> [PatchNotes.Version] {
            let ends = text.split(separator: "-", maxSplits: 1).map(String.init)
            guard let low = ends.first.flatMap(PatchNotes.Version.init), let high = ends.count == 2 ? PatchNotes.Version(ends[1]) : low,
                low <= high
            else { throw DevError("\(text) is not a version or A-B") }
            return tags.filter { low <= $0 && $0 <= high }
        }
    }
}
