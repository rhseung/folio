import Foundation

public struct CalendarExam: Codable, Sendable, Equatable {
    public var course: String
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String
    public var memo: String

    public init(course: String, title: String, start: Date, end: Date, location: String = "", memo: String = "") {
        self.course = course
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.memo = memo
    }
}
