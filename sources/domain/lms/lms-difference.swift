import Foundation

// 이미 받은 과제가 LMS와 다른 것이다. 받은 과제의 `lmsId`로 찾으므로 강의실의 과목을 몰라도 된다. 하나씩 승인하거나
// 무시하고, 한 번에 맞추는 단추는 두지 않는다.
public struct LMSDifference: Hashable, Sendable {
    public enum Change: Hashable, Sendable {
        // LMS에서는 냈는데 Folio에서는 아직 할 일이다.
        case submitted
        case due(folio: Date?, lms: Date)
    }

    public var lms: LMSAssignment
    public var course: UUID
    public var assignment: UUID
    public var change: Change

    public init(lms: LMSAssignment, course: UUID, assignment: UUID, change: Change) {
        self.lms = lms
        self.course = course
        self.assignment = assignment
        self.change = change
    }

    public var key: LMSKey {
        switch change {
        case .submitted: .init(kind: .submitted, id: lms.id)
        case .due(_, let date): .init(kind: .due, id: lms.id, stamp: Self.minute(date))
        }
    }

    // LMS 표는 분까지 적으므로 분 단위로 비교한다.
    static func minute(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 60).rounded(.down)) }

    // 마감이 지난 과제는 마감을 고쳐도 할 일이 바뀌지 않으므로, LMS 마감이 지나지 않았을 때만 다르다고 본다.
    static func find(_ lms: LMSAssignment, in a: Assignment, course: UUID, now: Date) -> [LMSDifference] {
        var out: [LMSDifference] = []
        if lms.submitted, a.status.isOpen {
            out.append(.init(lms: lms, course: course, assignment: a.id, change: .submitted))
        }
        if a.repeats == nil, let due = lms.due, due >= now, a.due.map(minute) != minute(due) {
            out.append(.init(lms: lms, course: course, assignment: a.id, change: .due(folio: a.due, lms: due)))
        }
        return out
    }
}
