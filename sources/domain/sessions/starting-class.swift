import Foundation

public struct StartingClass: Equatable, Sendable {
    public var courseId: UUID
    public var sessionId: UUID?
    public var start: Date
    public var end: Date

    public init(courseId: UUID, sessionId: UUID?, start: Date, end: Date) {
        self.courseId = courseId
        self.sessionId = sessionId
        self.start = start
        self.end = end
    }

    // 시간표의 수업을 그 시작 시각에 회차로 저장해도 키가 같아야, 그 수업에 한 일을 두 번 하지 않는다.
    public var key: String { "\(courseId.uuidString)@\(Int(start.timeIntervalSinceReferenceDate))" }
}
