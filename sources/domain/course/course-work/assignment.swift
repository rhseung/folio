import Foundation

public struct Assignment: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var title: String
    public var due: Date?
    public var status: AssignmentStatus
    // 낸 시각이다. "늦게 냄"은 상태가 아니라 이 시각과 마감을 견줘 센다. 그래서 마감을 고쳐도 표시가 따라간다.
    public var submittedAt: Date?
    // 과목의 지각 규칙(`GradePolicy.lateRule`)을 이 과제만 바꾼다.
    public var lateRule: LateRule?
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

extension Assignment {
    // 낸 상태가 되면 제출 시각을 남기고, 아직 내지 않은 상태나 못 냄으로 돌아가면 지운다. 채점됨은 낸 뒤의 상태라 남긴 시각을
    // 지키고, 시각을 모르면 지어내지 않는다. `at`은 바깥(LMS)이 아는 제출 시각이고, 주면 남긴 시각보다 앞선다.
    public mutating func set(_ new: AssignmentStatus, submittedAt at: Date? = nil, now: Date) {
        status = new
        switch new {
        case .submitted: submittedAt = at ?? submittedAt ?? now
        case .graded: submittedAt = at ?? submittedAt
        case .todo, .doing, .missed: submittedAt = nil
        }
    }

    public func isOverdue(at now: Date) -> Bool { status.isOpen && (due.map { $0 < now } ?? false) }
}
