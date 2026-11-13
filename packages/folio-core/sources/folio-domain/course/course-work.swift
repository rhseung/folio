import Foundation

/// One exam; maps 1:1 to its `Exams/<folder>` folder. A quiz and a final are the same thing here: what an exam counts
/// for is its grade component, what it covers is its scope.
public struct Exam: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var title: String
    /// Real clock time; exam times ignore the day boundary so they are never seen late.
    public var start: Date?
    public var end: Date?
    public var location: String
    public var scopeUnitIds: [UUID]
    public var scopeText: String
    /// Allowed materials (calculator, cheat sheet, ...).
    public var allowed: String
    public var componentId: UUID?
    public var memo: String
    public var plan: [ExamPlanItem]
    /// The prep folder's name under `Exams`, kept rather than worked out from the title: a renamed exam keeps its
    /// folder, and folders made before titles named them (`Midterm` for 중간고사) keep pointing at their files.
    public var folder: String?

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, title: String, start: Date? = nil, end: Date? = nil, location: String = "",
                folder: String? = nil) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.scopeUnitIds = []
        self.scopeText = ""
        self.allowed = ""
        self.memo = ""
        self.plan = []
        self.folder = folder
    }
}

extension Exam {
    // `plan` came after the first course.json files, so a missing key means no plan.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        updatedBy = try c.decode(DeviceID.self, forKey: .updatedBy)
        title = try c.decode(String.self, forKey: .title)
        start = try c.decodeIfPresent(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
        location = try c.decode(String.self, forKey: .location)
        scopeUnitIds = try c.decode([UUID].self, forKey: .scopeUnitIds)
        scopeText = try c.decode(String.self, forKey: .scopeText)
        allowed = try c.decode(String.self, forKey: .allowed)
        componentId = try c.decodeIfPresent(UUID.self, forKey: .componentId)
        memo = try c.decode(String.self, forKey: .memo)
        plan = try c.decodeIfPresent([ExamPlanItem].self, forKey: .plan) ?? []
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
    }
}

public enum AssignmentStatus: String, Codable, Sendable, CaseIterable {
    case todo, doing, submitted, graded

    public var isOpen: Bool { self == .todo || self == .doing }
}

public enum AssignmentSource: String, Codable, Sendable, CaseIterable {
    case manual, file, lms
}

public struct Assignment: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var title: String
    /// Real clock time, like exams.
    public var due: Date?
    public var status: AssignmentStatus
    public var componentId: UUID?
    /// A group of components it scores in all at once, one score each (a lab report graded on materials, results and
    /// discussion). Set instead of `componentId`.
    public var componentGroup: String?
    /// Only the next one exists; handing it in makes the one after (`CourseFile.continueRepeating`).
    public var repeats: AssignmentRepeat?
    public var problemMaterialId: UUID?
    public var submissionMaterialIds: [UUID]
    public var unitIds: [UUID]
    public var source: AssignmentSource
    /// The LMS assignment it was added from (`LMSAssignment.id`), so the LMS doesn't propose it again.
    public var lmsId: Int?
    public var memo: String

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, title: String, due: Date? = nil, source: AssignmentSource = .manual) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.title = title
        self.due = due
        self.status = .todo
        self.submissionMaterialIds = []
        self.unitIds = []
        self.source = source
        self.memo = ""
    }
}

extension CourseFile {
    /// Once a repeating assignment is handed in, the next one: on the rule's next deadline, same title, rule, group and
    /// component, as long as it falls by `end` and isn't there yet. Only the one just handed in moves the series on, so
    /// deleting a later one ends it.
    public mutating func continueRepeating(_ id: UUID, until end: Date?, calendar: Calendar, device: DeviceID, now: Date) {
        guard let a = assignments.first(where: { $0.id == id }), let rule = a.repeats, !a.status.isOpen, let due = a.due,
              !assignments.contains(where: { $0.title == a.title && ($0.due ?? .distantPast) > due }) else { return }
        let next = nextDue(after: due, rule: rule, title: a.title, calendar: calendar)
        guard end.map({ next <= $0 }) ?? true else { return }
        var made = Assignment(device: device, at: now, title: a.title, due: next)
        made.repeats = rule
        made.componentId = a.componentId
        made.componentGroup = a.componentGroup
        assignments.append(made)
    }

    /// The deadline after `due` in the series titled `title`. A monthly series keeps the day it started on, so one
    /// clamped to a short month's end goes back to the 31st; the sheet's hint and the next assignment both ask here.
    public func nextDue(after due: Date, rule: AssignmentRepeat, title: String, calendar: Calendar) -> Date {
        let first = (assignments.filter { $0.title == title && $0.repeats?.unit == .month }.compactMap(\.due) + [due]).min()!
        return rule.next(after: due, day: calendar.component(.day, from: first), calendar: calendar)
    }
}
