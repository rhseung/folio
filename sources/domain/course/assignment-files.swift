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

// 마감까지 남은 시간은 공부일 경계가 아니라 실제 시각으로 센다.
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

public enum DueUrgency: Int, Comparable, Sendable {
    case urgent, soon, later

    public init(studyDays days: Int) {
        self = days <= 1 ? .urgent : days < 7 ? .soon : .later
    }

    public init(due: Date, now: Date, settings: Settings, calendar: Calendar) {
        self.init(studyDays: settings.studyDays(from: now, until: due, calendar: calendar))
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

extension Settings {
    public func studyDays(from now: Date, until date: Date, calendar: Calendar) -> Int {
        studyDay(of: now, calendar: calendar).days(until: studyDay(of: date, calendar: calendar))
    }
}
