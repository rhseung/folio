import FolioDomain

// 다음 릴리스를 정하는 규칙이다. 패치 노트가 있는 PR이 머지되면 patch를 올리고, 기능 묶음이 끝나 사용자가 minor를
// 승인하면 매니저가 그 PR에 `minorLabel`을 붙인다. 지난 태그 뒤의 PR을 모두 보므로, 앞선 실행이 취소되어 건너뛴 PR도
// 다음 릴리스에 들어간다.
enum ReleasePlan {
    static let minorLabel = "release/minor"

    struct PR: Hashable {
        var merged: PatchNotes.Merged
        var labels: [String] = []
    }

    static func next(after latest: PatchNotes.Version?, prs: [PR]) -> PatchNotes.Version? {
        guard prs.contains(where: { !PatchNotes.items(in: $0.merged.body).isEmpty }) else { return nil }
        guard let latest else { return PatchNotes.Version(0, 1, 0) }
        if prs.contains(where: { $0.labels.contains(minorLabel) }) { return PatchNotes.Version(latest.major, latest.minor + 1, 0) }
        return PatchNotes.Version(latest.major, latest.minor, latest.patch + 1)
    }

    // 한 커밋에 태그가 둘일 수 있으므로(같은 커밋의 patch와 minor) 커밋이 아니라 버전으로 앞선 태그를 고른다.
    static func previous(before version: PatchNotes.Version, among tags: [PatchNotes.Version]) -> PatchNotes.Version? {
        tags.filter { $0 < version }.max()
    }
}
