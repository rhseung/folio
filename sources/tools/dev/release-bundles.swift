import Foundation

// 묶음은 이슈에 단 `bundle/<이름>` 라벨이다. 매니저가 묶음을 시작할 때 라벨을 붙여 제안하고, 사용자가 그 구성을 승인하면
// 묶음의 minor도 승인한 것이다.
enum ReleaseBundles {
    struct Label: Decodable { var name: String }

    struct Row: Decodable {
        var number: Int
        var title: String
        var state: String
    }

    static func all() throws -> [ReleasePlan.Bundle] {
        // `gh label list --search`는 이름의 앞부분이 아니라 설명의 낱말로도 찾으므로 모두 받아 거른다.
        let labels = try Shell.run("gh", "label", "list", "--limit", "1000", "--json", "name")
        return try list(Label.self, labels).compactMap { label in
            guard let name = ReleasePlan.bundleName(ofLabel: label.name) else { return nil }
            let json = try Shell.run(
                "gh", "issue", "list", "--label", label.name, "--state", "all", "--limit", "1000", "--json", "number,title,state")
            let issues = try list(Row.self, json).map {
                ReleasePlan.Issue(number: $0.number, title: $0.title, open: $0.state == "OPEN")
            }
            return ReleasePlan.Bundle(name: name, issues: issues)
        }
    }

    // gh는 찾은 라벨이 없으면 `[]` 대신 아무것도 쓰지 않는다.
    static func list<T: Decodable>(_ type: T.Type, _ json: String) throws -> [T] {
        json.isEmpty ? [] : try JSONDecoder().decode([T].self, from: Data(json.utf8))
    }
}
