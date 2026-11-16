import FolioDomain
import Foundation

// 버전의 원본은 `v<X.Y.Z>` 태그다. 상수에 두면 PR마다 올리는 patch가 동시에 열린 PR끼리 충돌한다.
enum ReleaseTags {
    static func name(_ version: PatchNotes.Version) -> String { "v\(version)" }

    static func versions(at ref: String) throws -> [PatchNotes.Version] {
        try Shell.run("git", "tag", "--merged", ref, "--list", "v*").split(separator: "\n").compactMap { PatchNotes.Version(String($0)) }
    }

    static func latest(at ref: String) throws -> PatchNotes.Version? { try versions(at: ref).max() }

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

    // 태그 시각도 그 커밋의 시각으로 둔다. 나중에 단 지난 버전의 태그도 제 날짜를 갖는다.
    static func create(_ version: PatchNotes.Version, at ref: String, push: Bool) throws {
        guard !exists(version) else { throw DevError("\(name(version)) already exists") }
        let sha = try Shell.run("git", "rev-parse", "--verify", "\(ref)^{commit}")
        let when = "@\(Int(try date(of: sha).timeIntervalSince1970)) +0000"
        try Shell.run("env", "GIT_COMMITTER_DATE=\(when)", "git", "tag", "-a", name(version), sha, "-m", "Folio \(version)")
        if push { try Shell.run("git", "push", "origin", "refs/tags/\(name(version))") }
    }

    static func body(for version: PatchNotes.Version, at ref: String, since: String? = nil, assets: Bool = true) throws -> String {
        let start = try since ?? ReleasePlan.previous(before: version, among: versions(at: ref)).map(name)
        let prs = try MergedPullRequests.between(start, and: ref).map(\.merged)
        return PatchNotes.releaseBody(prs, first: start == nil, date: try date(of: ref), assets: assets)
    }
}
