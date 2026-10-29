import Foundation

public enum AssignmentFiles {
    /// `HW 3` → `HW03`; titles that name no assignment kind are their own folder name.
    public static func folder(of assignment: Assignment) -> String {
        AssignmentKind.parse(title: assignment.title).map { $0.kind.folderName($0.number) } ?? assignment.title
    }

    /// `Assignments/HW03`, course-relative.
    public static func path(of assignment: Assignment) -> String {
        "\(CourseFolder.assignments.rawValue)/\(folder(of: assignment))"
    }

    /// Tracked files inside the assignment's folder, folder-relative paths kept as stored.
    public static func materials(of assignment: Assignment, in materials: [Material]) -> [Material] {
        let prefix = path(of: assignment) + "/"
        return materials.filter { $0.path.hasPrefix(prefix) && $0.status != .ignored }
    }

    /// `HW3-5070류현승.pdf`, `SP1_이름.pdf`: kind and number first, then a separator and more — the usual way a
    /// submission is named. Anything else in the folder (`26h3.pdf`) is taken as the problem.
    public static func guessKind(fileName: String) -> MaterialKind {
        let pattern = try! Regex("(?i)^(\(AssignmentKind.allCases.map(\.rawValue).joined(separator: "|")))\\s*\\d{1,2}[-_ ].+")
        return fileName.wholeMatch(of: pattern) != nil ? .submission : .problem
    }

    public static func suggestsSubmitted(_ assignment: Assignment, files: [Material]) -> Bool {
        (assignment.status == .todo || assignment.status == .doing)
            && files.contains { ($0.kind ?? guessKind(fileName: ($0.path as NSString).lastPathComponent)) == .submission }
    }
}

/// Where a deadline stands, for badges. Real clock time, not the study-day boundary (docs/SPEC.md "하루 경계").
public enum DueState: Equatable, Sendable {
    case none
    case overdue(days: Int)
    case hours(Int)
    case days(Int)

    public init(due: Date?, now: Date, calendar: Calendar) {
        guard let due else { self = .none; return }
        if due < now {
            self = .overdue(days: max(0, calendar.dateComponents([.day], from: due, to: now).day ?? 0))
        } else if due.timeIntervalSince(now) < 24 * 3600 {
            self = .hours(Int((due.timeIntervalSince(now) / 3600).rounded(.up)))
        } else {
            self = .days(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0)
        }
    }
}
