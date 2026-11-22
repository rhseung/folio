import Foundation

public struct PlannedNotification: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case assignmentDue(hoursBefore: Int)
        // 마감 지난 과제를 하루에 한 번 모아 알린다. 하나뿐이면 `subject`가 그 과제다.
        case assignmentOverdue(count: Int)
        case examDayBefore, examMorning
        // 앱이 이미 보낸 알림인지 알 수 있도록 `id`에 결석 횟수를 담는다.
        case attendanceOneAway(absences: Int)
    }

    // 다시 예약할 때 요청을 하나 더 만들지 않고 바꾸도록, 다시 만들어도 같은 값이어야 한다.
    public var id: String
    public var date: Date
    public var kind: Kind
    public var courseId: UUID?
    public var subject: String
    public var at: Date?
}
