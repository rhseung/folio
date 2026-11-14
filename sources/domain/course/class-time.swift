import Foundation

public struct ClassTime: Codable, Sendable, Hashable {
    // ISO 8601 요일이다. 1은 월요일, 7은 일요일이다.
    public var weekday: Int
    public static let weekdayNames = [
        LocalizedStringResource.weekdayMon, .weekdayTue, .weekdayWed, .weekdayThu, .weekdayFri, .weekdaySat, .weekdaySun,
    ]
    .map { String(localized: $0) }
    public var startMinute: Int
    public var endMinute: Int
    public var room: String
    public var link: String?

    public init(weekday: Int, startMinute: Int, endMinute: Int, room: String = "", link: String? = nil) {
        self.weekday = weekday
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.room = room
        self.link = link
    }
}
