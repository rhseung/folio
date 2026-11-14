import Foundation

public enum AssignmentFiles {
    public static func folder(of assignment: Assignment) -> String {
        AssignmentKind.parse(title: assignment.title).map { $0.kind.folderName($0.number) } ?? assignment.title
    }

    public static func path(of assignment: Assignment) -> String {
        "\(CourseFolder.assignments.rawValue)/\(folder(of: assignment))"
    }

    public static func materials(of assignment: Assignment, in materials: [Material]) -> [Material] {
        let prefix = path(of: assignment) + "/"
        return materials.filter { $0.path.hasPrefix(prefix) && $0.status != .ignored }
    }

    public static func guessKind(fileName: String) -> MaterialKind {
        let pattern = try! Regex("(?i)^(\(AssignmentKind.allCases.map(\.rawValue).joined(separator: "|")))\\s*\\d{1,2}[-_ ].+")
        return fileName.wholeMatch(of: pattern) != nil ? .submission : .problem
    }

    public static func suggestsSubmitted(_ assignment: Assignment, files: [Material]) -> Bool {
        (assignment.status == .todo || assignment.status == .doing)
            && files.contains { ($0.kind ?? guessKind(fileName: ($0.path as NSString).lastPathComponent)) == .submission }
    }
}

extension Settings {
    public func studyDays(from now: Date, until date: Date, calendar: Calendar) -> Int {
        studyDay(of: now, calendar: calendar).days(until: studyDay(of: date, calendar: calendar))
    }
}
