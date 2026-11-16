import Foundation

// 강의실에서 받을 때 고른 과목이다. 설정에서 미리 잇지 않고, 받을 때 고른 과목을 다음 받기에 미리 고른다.
// `course`가 nil인 기억은 "과목 없음"이다(소방 교육처럼 과목이 아닌 강의실). 기억이 아예 없는 강의실과 구분한다.
public struct LMSRoom: Codable, Hashable, Sendable {
    public var course: UUID?

    public init(course: UUID? = nil) { self.course = course }
}
