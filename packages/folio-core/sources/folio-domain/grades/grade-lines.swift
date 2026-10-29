import Foundation

/// A course's components in order, each followed by its scores. A run of components sharing a group sits under one
/// heading weighing the whole run.
public enum GradeLine: Sendable, Equatable, Identifiable {
    case group(String, weight: Double, first: UUID)
    case component(GradeComponent, indented: Bool)
    case entry(ScoreEntry, indented: Bool)

    public var id: String {
        switch self {
        // Keyed by its first component: two runs apart can share a group name.
        case .group(_, _, let first): "group-\(first.uuidString)"
        case .component(let c, _): c.id.uuidString
        case .entry(let e, _): e.id.uuidString
        }
    }

    /// `components` sorted by order.
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
