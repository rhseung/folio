import FolioCore
import Foundation

// 새 항목을 만들 때 채우는 시각과 길이다. 시각은 자정부터 센 분이다.
public struct ScheduleDefaults: Codable, Sendable, Equatable {
    public var dueMinute = SettingItem.dueMinute.int
    public var examStartMinute = SettingItem.examStartMinute.int
    public var examMinutes = SettingItem.examMinutes.int
    public var sessionStartMinute = SettingItem.sessionStartMinute.int
    public var classStartMinute = SettingItem.classStartMinute.int

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        dueMinute = try c.value(.dueMinute, or: d.dueMinute)
        examStartMinute = try c.value(.examStartMinute, or: d.examStartMinute)
        examMinutes = try c.value(.examMinutes, or: d.examMinutes)
        sessionStartMinute = try c.value(.sessionStartMinute, or: d.sessionStartMinute)
        classStartMinute = try c.value(.classStartMinute, or: d.classStartMinute)
    }
}

extension ScheduleDefaults {
    // 새 시험은 내일 기본 시각에 둔다. 오늘로 두면 대개 이미 지난 시각이다.
    public func examStart(after now: Date, calendar: Calendar) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(atMinute: examStartMinute, of: tomorrow) ?? tomorrow
    }

    // 시험이 다음 날로 넘어가지 않게 그날의 마지막 분에서 멈춘다.
    public func examEndMinute(startMinute: Int?) -> Int {
        min((startMinute ?? examStartMinute) + examMinutes, 23 * 60 + 59)
    }

    public func due(on day: Date, calendar: Calendar) -> Date { calendar.date(atMinute: dueMinute, of: day) ?? day }

    public func sessionStart(on day: Date, calendar: Calendar) -> Date { calendar.date(atMinute: sessionStartMinute, of: day) ?? day }
}

extension Settings {
    public var newClassTime: ClassTime {
        ClassTime(
            weekday: 1, startMinute: schedule.classStartMinute, endMinute: min(schedule.classStartMinute + classMinutes, 24 * 60 - 1),
            room: "")
    }
}
