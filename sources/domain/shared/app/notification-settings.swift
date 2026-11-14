import Foundation

public struct NotificationSettings: Codable, Sendable, Equatable {
    public var assignmentDue = true
    public var assignmentLeadHours = [24, 3]
    public var examDayBefore = true
    public var examDayBeforeMinute = 21 * 60
    public var examMorning = true
    public var examMorningMinute = 8 * 60
    public var dailyReview = true
    public var dailyReviewMinute = 9 * 60
    public var attendance = true

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        assignmentDue = try c.value(.assignmentDue, or: d.assignmentDue)
        assignmentLeadHours = try c.value(.assignmentLeadHours, or: d.assignmentLeadHours)
        examDayBefore = try c.value(.examDayBefore, or: d.examDayBefore)
        examDayBeforeMinute = try c.value(.examDayBeforeMinute, or: d.examDayBeforeMinute)
        examMorning = try c.value(.examMorning, or: d.examMorning)
        examMorningMinute = try c.value(.examMorningMinute, or: d.examMorningMinute)
        dailyReview = try c.value(.dailyReview, or: d.dailyReview)
        dailyReviewMinute = try c.value(.dailyReviewMinute, or: d.dailyReviewMinute)
        attendance = try c.value(.attendance, or: d.attendance)
    }
}
