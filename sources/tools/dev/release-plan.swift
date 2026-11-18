import FolioDomain

// 다음 릴리스들을 정하는 규칙이다. 지난 태그 뒤에 머지된 PR을 머지 순서로 보고, 패치 노트가 있는 PR마다 그 머지 커밋에서
// 버전을 하나씩 낸다. 노트 없는 PR은 다음 노트 있는 PR의 버전에 담긴다. 앞선 실행이 취소되어 건너뛴 PR도 지난 태그 뒤에
// 남아 있으므로 다음 실행에서 따로 나온다.
//
// minor는 두 길로 온다. 묶음(`bundle/<이름>` 라벨을 단 이슈들)의 마지막 이슈를 닫는 PR, 또는 사람이 `minorLabel`을 붙인
// PR이다. 그 PR에 노트가 없으면 minor는 다음 노트 있는 PR로 넘어간다.
enum ReleasePlan {
    static let minorLabel = "release/minor"
    static let bundlePrefix = "bundle/"

    struct PR: Hashable {
        var merged: PatchNotes.Merged
        var labels: [String] = []
        var commit = ""
        var closes: [Int] = []

        var hasNotes: Bool { !PatchNotes.items(in: merged.body).isEmpty }
    }

    struct Issue: Hashable {
        var number: Int
        var title: String
        var open: Bool
    }

    struct Bundle: Hashable {
        var name: String
        var issues: [Issue]

        var open: [Issue] { issues.filter(\.open) }
        var numbers: Set<Int> { Set(issues.map(\.number)) }
    }

    struct Step: Hashable {
        var version: PatchNotes.Version
        var commit: String
        var bundles: [String] = []
        // 이 버전에 담기는 PR이다. 앞 버전 뒤의 노트 없는 PR과 이 버전을 낸 PR이다.
        var prs: [Int] = []
    }

    static func bump(_ latest: PatchNotes.Version?, minor: Bool) -> PatchNotes.Version {
        guard let latest else { return PatchNotes.Version(0, 1, 0) }
        return minor
            ? PatchNotes.Version(latest.major, latest.minor + 1, 0) : PatchNotes.Version(latest.major, latest.minor, latest.patch + 1)
    }

    // `released`는 이미 minor를 낸 묶음이다(태그 메시지에 적는다). 끝난 묶음에 이슈를 더 넣고 닫아도 minor를 다시 내지 않는다.
    static func steps(after latest: PatchNotes.Version?, prs: [PR], bundles: [Bundle] = [], released: Set<String> = []) -> [Step] {
        var last = latest
        var minor = false
        var ending: [String] = []
        var done = released
        var steps: [Step] = []
        var included: [Int] = []
        for (i, pr) in prs.enumerated() {
            included.append(pr.merged.number)
            if pr.labels.contains(minorLabel) { minor = true }
            for bundle in bundles where !done.contains(bundle.name) && ends(bundle, at: i, in: prs) {
                minor = true
                ending.append(bundle.name)
                done.insert(bundle.name)
            }
            guard pr.hasNotes else { continue }
            let version = bump(last, minor: minor)
            steps.append(Step(version: version, commit: pr.commit, bundles: ending, prs: included))
            last = version
            minor = false
            ending = []
            included = []
        }
        return steps
    }

    // 묶음은 열린 이슈가 없고, 그 이슈를 닫은 PR 중 마지막인 PR에서 끝난다. 이슈를 손으로 닫았어도 그 앞의 PR이
    // 묶음의 이슈를 닫았다면 그 PR에서 끝난다. 그 PR이 이미 지난 태그 앞에 있으면(낸 뒤에 남은 이슈를 손으로 닫았으면)
    // `prs`에 닫는 PR이 없으므로 첫 PR에서 끝낸다. 그러지 않으면 그 묶음의 minor는 영영 나오지 않는다.
    static func ends(_ bundle: Bundle, at index: Int, in prs: [PR]) -> Bool {
        guard bundle.open.isEmpty, !bundle.issues.isEmpty else { return false }
        let numbers = bundle.numbers
        let closing = { (pr: PR) in pr.closes.contains(where: numbers.contains) }
        guard let last = prs.lastIndex(where: closing) else { return index == 0 }
        return index == last
    }

    // 태그는 게시 바로 앞에 달지만, 사람이 단 태그의 실행이 대기 중에 취소되거나 태그와 게시 사이에서 실행이 멈추면
    // 게시되지 않은 태그가 남는다. 그런 태그를 먼저 게시한다.
    static func pending(tags: [PatchNotes.Version], published: Set<PatchNotes.Version>) -> [PatchNotes.Version] {
        tags.filter { !published.contains($0) }.sorted()
    }

    // 한 커밋에 태그가 둘일 수 있으므로(같은 커밋의 patch와 minor) 커밋이 아니라 버전으로 앞선 태그를 고른다.
    static func previous(before version: PatchNotes.Version, among tags: [PatchNotes.Version]) -> PatchNotes.Version? {
        tags.filter { $0 < version }.max()
    }

    static func bundleName(ofLabel label: String) -> String? {
        guard label.hasPrefix(bundlePrefix) else { return nil }
        let name = label.dropFirst(bundlePrefix.count).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    // release 실행 요약에 적는다. 끝나지 않을 이슈가 섞여 minor가 막힌 묶음을 바로 보게 한다.
    static func summary(_ bundles: [Bundle], released: Set<String>) -> String {
        let shown = bundles.filter { !released.contains($0.name) && !$0.issues.isEmpty }.sorted { $0.name < $1.name }
        guard !shown.isEmpty else { return "## 남은 묶음\n열린 묶음이 없습니다.\n" }
        let parts = shown.map { bundle -> String in
            let open = bundle.open.sorted { $0.number < $1.number }
            guard !open.isEmpty else {
                return "### \(bundle.name)\n이슈 \(bundle.issues.count)개가 모두 닫혔고 아직 minor를 내지 않았습니다.\n"
            }
            let rows = open.map { "- #\($0.number) \($0.title)" }.joined(separator: "\n")
            return "### \(bundle.name)\n이슈 \(bundle.issues.count)개 중 \(open.count)개가 남았습니다.\n\(rows)\n"
        }
        return "## 남은 묶음\n" + parts.joined(separator: "\n")
    }
}
