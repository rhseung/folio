import FolioDomain
import Foundation

// 버전의 원본은 `v<X.Y.Z>` 태그다. 상수에 두면 PR마다 올리는 patch가 동시에 열린 PR끼리 충돌한다.
enum ReleaseTags {
    static func name(_ version: PatchNotes.Version) -> String { "v\(version)" }

    static func versions(at ref: String) throws -> [PatchNotes.Version] {
        try Shell.run("git", "tag", "--merged", ref, "--list", "v*").split(separator: "\n").compactMap { PatchNotes.Version(String($0)) }
    }

    static func latest(at ref: String) throws -> PatchNotes.Version? { try versions(at: ref).max() }

    static func all() throws -> [PatchNotes.Version] {
        try Shell.run("git", "tag", "--list", "v*").split(separator: "\n").compactMap { PatchNotes.Version(String($0)) }
    }

    struct Release: Decodable {
        var tagName: String
        var isDraft: Bool
    }

    // 초안은 앱이 읽지 않으므로 게시하지 않은 것으로 센다.
    static func published() throws -> Set<PatchNotes.Version> {
        let json = try Shell.run("gh", "release", "list", "--limit", "1000", "--json", "tagName,isDraft")
        let rows = try JSONDecoder().decode([Release].self, from: Data(json.utf8))
        return Set(rows.filter { !$0.isDraft }.compactMap { PatchNotes.Version($0.tagName) })
    }

    static func exists(_ version: PatchNotes.Version) -> Bool {
        (try? Shell.run("git", "rev-parse", "-q", "--verify", "refs/tags/\(name(version))")) != nil
    }

    // squash 머지 커밋의 커미터 시각이 머지한 시각이다.
    static func date(of ref: String) throws -> Date {
        guard let seconds = TimeInterval(try Shell.run("git", "log", "-1", "--format=%ct", ref)) else {
            throw DevError("no commit time for \(ref)")
        }
        return Date(timeIntervalSince1970: seconds)
    }

    // 태그 시각도 그 커밋의 시각으로 둔다. 나중에 단 지난 버전의 태그도 제 날짜를 갖는다. minor를 낸 묶음은 태그 메시지에
    // 남겨, 같은 묶음이 minor를 두 번 내지 않게 하고 게시되지 않은 태그를 다시 게시할 때도 묶음 이름을 잃지 않는다.
    static func create(_ version: PatchNotes.Version, at ref: String, bundles: [String] = [], push: Bool) throws {
        guard !exists(version) else { throw DevError("\(name(version)) already exists") }
        let sha = try Shell.run("git", "rev-parse", "--verify", "\(ref)^{commit}")
        let when = "@\(Int(try date(of: sha).timeIntervalSince1970)) +0000"
        let message = (["Folio \(version)"] + (bundles.isEmpty ? [] : [""] + bundles.map { bundleTrailer + $0 })).joined(separator: "\n")
        try Shell.run("env", "GIT_COMMITTER_DATE=\(when)", "git", "tag", "-a", name(version), sha, "-m", message)
        if push { try Shell.run("git", "push", "origin", "refs/tags/\(name(version))") }
    }

    // 릴리스가 있으면 릴리스와 태그를 함께 지우고, 없으면 원격과 로컬의 태그만 지운다.
    static func delete(_ version: PatchNotes.Version, published: Bool) throws {
        if published {
            try Shell.run("gh", "release", "delete", name(version), "--cleanup-tag", "--yes")
        } else {
            try Shell.run("git", "push", "origin", ":refs/tags/\(name(version))")
        }
        if exists(version) { try Shell.run("git", "tag", "-d", name(version)) }
    }

    // 노트만 있는 릴리스다. 그 커밋의 코드 버전은 태그와 다르므로 앱을 빌드하지 않는다.
    static func publish(_ version: PatchNotes.Version, body: String) throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "folio-\(version)-notes.md")
        try body.write(to: file, atomically: true, encoding: .utf8)
        try Shell.run("gh", "release", "create", name(version), "--verify-tag", "--title", "Folio \(version)", "--notes-file", file.path())
    }

    static let bundleTrailer = "Bundle: "

    static func bundles(inMessage message: String) -> [String] {
        message.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix(bundleTrailer) else { return nil }
            let name = line.dropFirst(bundleTrailer.count).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
    }

    static func bundles(of version: PatchNotes.Version) throws -> [String] {
        guard exists(version) else { return [] }
        return bundles(inMessage: try Shell.run("git", "tag", "-l", name(version), "--format=%(contents)"))
    }

    // 모든 태그를 본다. 다시 매기며 지운 태그는 빠진다.
    static func releasedBundles() throws -> Set<String> {
        Set(bundles(inMessage: try Shell.run("git", "tag", "-l", "v*", "--format=%(contents)")))
    }

    static func body(for version: PatchNotes.Version, at ref: String, since: String? = nil, assets: Bool = true) throws -> String {
        let start = try since ?? ReleasePlan.previous(before: version, among: versions(at: ref)).map(name)
        let prs = try MergedPullRequests.between(start, and: ref).map(\.merged)
        return PatchNotes.releaseBody(prs, first: start == nil, date: try date(of: ref), assets: assets)
    }
}
