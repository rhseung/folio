import Foundation

public enum AssignmentFiles {
    public static func folder(of assignment: Assignment, kinds: [AssignmentKind] = AssignmentKind.builtIn) -> String {
        AssignmentKind.parse(title: assignment.title, kinds: kinds).map { $0.kind.folderName($0.number) } ?? assignment.title
    }

    public static func path(of assignment: Assignment, kinds: [AssignmentKind] = AssignmentKind.builtIn) -> String {
        "\(CourseFolder.assignments.rawValue)/\(folder(of: assignment, kinds: kinds))"
    }

    public static func materials(
        of assignment: Assignment, in materials: [Material], kinds: [AssignmentKind] = AssignmentKind.builtIn
    ) -> [Material] {
        let prefix = path(of: assignment, kinds: kinds) + "/"
        return materials.filter { $0.path.hasPrefix(prefix) && $0.status != .ignored }
    }

    public static func guessKind(fileName: String, kinds: [AssignmentKind] = AssignmentKind.builtIn) -> MaterialKind {
        let prefixes = kinds.map { NSRegularExpression.escapedPattern(for: $0.prefix) }.joined(separator: "|")
        guard !kinds.isEmpty, let pattern = try? Regex("(?i)^(\(prefixes))\\s*\\d{1,2}[-_ ].+") else { return .problem }
        return fileName.wholeMatch(of: pattern) != nil ? .submission : .problem
    }

    public static func suggestsSubmitted(
        _ assignment: Assignment, files: [Material], kinds: [AssignmentKind] = AssignmentKind.builtIn
    ) -> Bool {
        (assignment.status == .todo || assignment.status == .doing)
            && files.contains { ($0.kind ?? guessKind(fileName: ($0.path as NSString).lastPathComponent, kinds: kinds)) == .submission }
    }
}
