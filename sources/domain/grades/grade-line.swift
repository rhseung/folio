import Foundation

public enum GradeLine: Sendable, Equatable, Identifiable {
    case group(String, weight: Double, first: UUID)
    case component(GradeComponent, indented: Bool)
    case entry(ScoreEntry, indented: Bool)

    public var id: String {
        switch self {
        // 떨어져 있는 두 묶음이 같은 그룹 이름을 쓸 수 있으므로, 묶음의 첫 구성 요소로 키를 정한다.
        case .group(_, _, let first): "group-\(first.uuidString)"
        case .component(let c, _): c.id.uuidString
        case .entry(let e, _): e.id.uuidString
        }
    }

    public static func lines(_ components: [GradeComponent], scores: [ScoreEntry]) -> [GradeLine] {
        var lines: [GradeLine] = []
        for (i, c) in components.enumerated() {
            if let group = c.group, i == 0 || components[i - 1].group != group {
                let run = components[i...].prefix { $0.group == group }
                lines.append(.group(group, weight: run.map(\.weight).reduce(0, +), first: c.id))
            }
            lines.append(.component(c, indented: c.group != nil))
            lines += scores.filter { $0.componentId == c.id }.map { .entry($0, indented: c.group != nil) }
        }
        return lines
    }
}
