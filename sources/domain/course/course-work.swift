import Foundation

public struct Exam: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var title: String
    public var start: Date?
    public var end: Date?
    public var location: String
    public var scopeUnitIds: [UUID]
    public var scopeText: String
    public var allowed: String
    public var componentId: UUID?
    public var memo: String
    public var plan: [ExamPlanItem]
    // 폴더 이름을 제목에서 계산하지 않고 저장한다. 그래야 제목을 바꾼 시험도 폴더를 지키고, 제목으로 폴더 이름을 짓기
    // 전에 만든 폴더(중간고사의 `Midterm`)도 계속 그 파일을 가리킨다.
    public var folder: String?

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, title: String, start: Date? = nil, end: Date? = nil, location: String = "",
        folder: String? = nil
    ) {
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
    // `plan`은 첫 course.json 파일들보다 나중에 생겼으므로, 키가 없으면 계획이 없다는 뜻이다.
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
    public var due: Date?
    public var status: AssignmentStatus
    public var componentId: UUID?
    public var componentGroup: String?
    public var repeats: AssignmentRepeat?
    public var problemMaterialId: UUID?
    public var submissionMaterialIds: [UUID]
    public var unitIds: [UUID]
    public var source: AssignmentSource
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
    public mutating func continueRepeating(_ id: UUID, until end: Date?, calendar: Calendar, device: DeviceID, now: Date) {
        guard let a = assignments.first(where: { $0.id == id }), let rule = a.repeats, !a.status.isOpen, let due = a.due,
            !assignments.contains(where: { $0.title == a.title && ($0.due ?? .distantPast) > due })
        else { return }
        let next = nextDue(after: due, rule: rule, title: a.title, calendar: calendar)
        guard end.map({ next <= $0 }) ?? true else { return }

        var made = Assignment(device: device, at: now, title: a.title, due: next)
        made.repeats = rule
        made.componentId = a.componentId
        made.componentGroup = a.componentGroup
        assignments.append(made)
    }

    // 월 반복은 처음 시작한 날을 지킨다. 그래서 짧은 달의 말일로 당겨진 마감도 다음 달에는 31일로 돌아간다.
    public func nextDue(after due: Date, rule: AssignmentRepeat, title: String, calendar: Calendar) -> Date {
        let first = (assignments.filter { $0.title == title && $0.repeats?.unit == .month }.compactMap(\.due) + [due]).min()!
        return rule.next(after: due, day: calendar.component(.day, from: first), calendar: calendar)
    }
}
