import FolioDomain
import Foundation

// main은 스쿼시 머지만 받아 PR마다 커밋이 하나이므로, 머지 커밋이 since..until에 있는 PR만 센다. 검색은 결과를 줄이려고
// <since>의 날짜로만 자르므로, 실제로 넣을 PR은 커밋으로 정한다.
enum MergedPullRequests {
    struct Row: Decodable {
        var number: Int
        var title: String
        var body: String
        var mergeCommit: [String: String]?
        var labels: [[String: String]]?
    }

    static func between(_ since: String?, and until: String) throws -> [ReleasePlan.PR] {
        let range = since.map { "\($0)..\(until)" } ?? until
        let commits = Set(try Shell.run("git", "rev-list", range).split(separator: "\n").map(String.init))
        guard !commits.isEmpty else { return [] }
        var search = "base:main"
        // 커밋 시각의 시간대와 검색의 UTC가 하루 어긋날 수 있어 하루 앞에서 자른다.
        if let since {
            let day = try ReleaseTags.date(of: since).addingTimeInterval(-86_400)
            search += " merged:>=" + day.formatted(.iso8601.year().month().day())
        }
        let json = try Shell.run(
            "gh", "pr", "list", "--state", "merged", "--search", search, "--limit", "1000",
            "--json", "number,title,body,mergeCommit,labels")
        return try JSONDecoder().decode([Row].self, from: Data(json.utf8))
            .filter { $0.mergeCommit?["oid"].map(commits.contains) ?? false }
            .sorted { $0.number < $1.number }
            .map {
                ReleasePlan.PR(
                    merged: PatchNotes.Merged(number: $0.number, title: $0.title, body: $0.body),
                    labels: ($0.labels ?? []).compactMap { $0["name"] })
            }
    }
}
