import Foundation

public struct NotificationSettings: Codable, Sendable, Equatable {
    public var assignmentDue = SettingItem.assignmentDue.bool
    public var assignmentLeadHours = SettingItem.assignmentLeadHours.ints
    public var examDayBefore = SettingItem.examDayBefore.bool
    public var examDayBeforeMinute = SettingItem.examDayBeforeMinute.int
    public var examMorning = SettingItem.examMorning.bool
    public var examMorningMinute = SettingItem.examMorningMinute.int
    public var dailyReview = SettingItem.dailyReview.bool
    public var dailyReviewMinute = SettingItem.dailyReviewMinute.int
    public var attendance = SettingItem.attendance.bool

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
