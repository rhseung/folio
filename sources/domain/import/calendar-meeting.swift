import Foundation

public struct CalendarMeeting: Codable, Sendable, Equatable {
    public var course: String
    public var start: Date
    public var end: Date
    public var room: String
    public var topic: String
    public var lab: Int?

    public init(course: String, start: Date, end: Date, room: String = "", topic: String = "", lab: Int? = nil) {
        self.course = course
        self.start = start
        self.end = end
        self.room = room
        self.topic = topic
        self.lab = lab
    }
}
