import Foundation

public struct LMSSnapshot: Codable, Hashable, Sendable {
    public var at: Date
    public var classrooms: [LMSClassroom]
    public var assignments: [LMSAssignment]
    public var files: [LMSFile]
    public var notices: [LMSNotice]

    public init(
        at: Date, classrooms: [LMSClassroom] = [], assignments: [LMSAssignment] = [], files: [LMSFile] = [],
        notices: [LMSNotice] = []
    ) {
        self.at = at
        self.classrooms = classrooms
        self.assignments = assignments
        self.files = files
        self.notices = notices
    }

    public func current(in classroom: Int) -> [LMSKey] {
        files.filter { $0.classroom == classroom }.map(\.key) + notices.filter { $0.classroom == classroom }.map(\.key)
    }

    public mutating func merge(_ other: LMSSnapshot, in classroom: Int) {
        assignments.removeAll { $0.classroom == classroom }
        files.removeAll { $0.classroom == classroom }
        notices.removeAll { $0.classroom == classroom }
        assignments += other.assignments.filter { $0.classroom == classroom }
        files += other.files.filter { $0.classroom == classroom }
        notices += other.notices.filter { $0.classroom == classroom }
    }
}
