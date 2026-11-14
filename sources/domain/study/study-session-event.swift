import Foundation

public struct StudySessionEvent: LogEvent, Equatable {
    public static let type = "study_session"
    public var courseId: UUID
    public var start: Date
    public var end: Date
    public var screen: String

    public init(courseId: UUID, start: Date, end: Date, screen: String) {
        self.courseId = courseId
        self.start = start
        self.end = end
        self.screen = screen
    }
}
