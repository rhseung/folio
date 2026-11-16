import Foundation

// LMS 탭 "이번 주 기한"의 행이다. 제안이 아니라 보기만 하고, Folio에 받은 과제와 받지 않은 과제를 함께 보인다.
public struct LMSDeadline: Hashable, Sendable, Identifiable {
    public var assignment: LMSAssignment
    public var classroom: LMSClassroom
    // 받은 과목이다. nil이면 아직 받지 않았다.
    public var course: UUID?

    public init(assignment: LMSAssignment, classroom: LMSClassroom, course: UUID? = nil) {
        self.assignment = assignment
        self.classroom = classroom
        self.course = course
    }

    public var id: Int { assignment.id }
}
