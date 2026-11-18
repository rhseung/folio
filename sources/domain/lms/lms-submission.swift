import Foundation

// LMS에서 낸 받은 과제다. 파일을 옮기거나 지우는 일이 아니라서 승인을 묻지 않고 동기화가 바로 제출함으로 바꾼다.
public struct LMSSubmission: Codable, Hashable, Sendable {
    public var course: Course.ID
    public var assignment: Assignment.ID
    public var lms: Int
    // LMS 과제 페이지의 마지막 제출 시각이다. 페이지를 읽지 못했으면 nil이고, 그러면 바꾼 시각을 낸 시각으로 적는다.
    public var at: Date?

    public init(course: Course.ID, assignment: Assignment.ID, lms: Int, at: Date? = nil) {
        (self.course, self.assignment, self.lms, self.at) = (course, assignment, lms, at)
    }

    public var key: LMSKey { .init(kind: .submitted, id: lms) }
}
