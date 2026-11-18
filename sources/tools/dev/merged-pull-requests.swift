import FolioDomain
import Foundation

// main은 스쿼시 머지만 받아 PR마다 커밋이 하나이므로, 머지 커밋이 since..until에 있는 PR만 센다. 검색은 결과를 줄이려고
// <since>의 날짜로만 자르므로, 실제로 넣을 PR은 커밋으로 정한다. PR 번호는 머지 순서가 아니므로 커밋 순서로 늘어놓는다.
enum MergedPullRequests {
    struct Reference: Decodable { var number: Int }

    struct Row: Decodable {
        var number: Int
        var title: String
        var body: String
        var mergeCommit: [String: String]?
        var labels: [[String: String]]?
        var closingIssuesReferences: [Reference]?
    }

    static func between(_ since: String?, and until: String) throws -> [ReleasePlan.PR] {
        let range = since.map { "\($0)..\(until)" } ?? until
        let commits = try Shell.run("git", "rev-list", "--reverse", range).split(separator: "\n").map(String.init)
        guard !commits.isEmpty else { return [] }
        let order = Dictionary(commits.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var search = "base:main"
        // 커밋 시각의 시간대와 검색의 UTC가 하루 어긋날 수 있어 하루 앞에서 자른다.
        if let since {
            let day = try ReleaseTags.date(of: since).addingTimeInterval(-86_400)
            search += " merged:>=" + day.formatted(.iso8601.year().month().day())
        }
        let json = try Shell.run(
            "gh", "pr", "list", "--state", "merged", "--search", search, "--limit", "1000",
            "--json", "number,title,body,mergeCommit,labels,closingIssuesReferences")
        return try JSONDecoder().decode([Row].self, from: Data(json.utf8))
            .compactMap { row -> (Int, ReleasePlan.PR)? in
                guard let commit = row.mergeCommit?["oid"], let position = order[commit] else { return nil }
                let pr = ReleasePlan.PR(
                    merged: PatchNotes.Merged(number: row.number, title: row.title, body: row.body),
                    labels: (row.labels ?? []).compactMap { $0["name"] }, commit: commit,
                    closes: (row.closingIssuesReferences ?? []).map(\.number))
                return (position, pr)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    static func mergeCommit(of number: Int) throws -> String {
        struct View: Decodable {
            var state: String
            var mergeCommit: [String: String]?
        }
        let json = try Shell.run("gh", "pr", "view", String(number), "--json", "state,mergeCommit")
        let view = try JSONDecoder().decode(View.self, from: Data(json.utf8))
        guard view.state == "MERGED", let oid = view.mergeCommit?["oid"] else { throw DevError("#\(number) is not merged") }
        return oid
    }
}
