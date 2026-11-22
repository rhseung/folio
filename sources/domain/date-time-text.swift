import FolioCore
import Foundation

// 날짜를 지금에 견줘 쓰는 표기는 여기 하나다. 오늘·내일·어제, 일주일 안이면 요일("수요일"), 그보다 멀면 날짜("12/2(수)")다.
// 시각을 함께 쓰면 오늘은 날 없이 시각만 쓰고, 한 시간 안이면 "45분 뒤"처럼 남은 때로 쓴다. 날 수는 공부일(하루 경계)로 센다.
public enum DateTimeText {
    public struct Parts: Equatable, Sendable {
        public var day: String?
        public var time: String?
        public var text: String { [day, time].compactMap(\.self).joined(separator: " ") }
    }

    // 이보다 가까우면 시각 대신 남은 때를 쓴다. 시각을 읽고 빼 보지 않아도 급한 것이 보이는 거리다.
    public static let soonMinutes = 60

    // 종일 일정의 자정을 공부일로 바꾸면 하루 경계 앞이라 전날이 된다. 그래서 시각이 없는 날짜는 달력 날짜 그대로 센다.
    public static func days(_ date: Date, from now: Date, settings: Settings, calendar: Calendar) -> Int {
        let day = hasTime(date, calendar: calendar) ? settings.studyDay(of: date, calendar: calendar) : LocalDate(date, in: calendar)
        return settings.studyDay(of: now, calendar: calendar).days(until: day)
    }

    // 종일 일정에서 가져온 마감과 시험은 자정에 놓인다. 그 자정은 시각이 아니므로 시각을 쓰라고 해도 쓰지 않는다.
    public static func hasTime(_ date: Date, calendar: Calendar) -> Bool { date != calendar.startOfDay(for: date) }

    public static func text(
        _ date: Date, from now: Date, time: Bool = false, settings: Settings, calendar: Calendar, locale: Locale = .autoupdatingCurrent
    ) -> String {
        parts(date, from: now, time: time, settings: settings, calendar: calendar, locale: locale).text
    }

    // 두 줄로 나눠 그리는 곳(과제 목록의 날짜 칸)이 쓰는 조각이다. 한 줄로 이으면 `text`와 같다.
    public static func parts(
        _ date: Date, from now: Date, time: Bool = false, settings: Settings, calendar: Calendar, locale: Locale = .autoupdatingCurrent
    ) -> Parts {
        let timed = time && hasTime(date, calendar: calendar)
        if timed, let soon = soon(date, from: now) { return Parts(day: nil, time: soon) }
        let days = days(date, from: now, settings: settings, calendar: calendar)
        let day: String? =
            switch abs(days) {
            case 0 where timed: nil
            case 0: String(localized: .dateTimeToday)
            case 1: String(localized: days > 0 ? .dateTimeTomorrow : .dateTimeYesterday)
            case ..<7: String(localized: .dateTimeWeekday(ClassTime.weekdayNames[calendar.isoWeekday(of: date) - 1]))
            default: CourseFile.day(date, calendar: calendar)
            }
        return Parts(day: day, time: timed ? clock(date, calendar: calendar, locale: locale) : nil)
    }

    // 날을 견주지 않고 날짜를 그대로 쓰는 곳(다가오는 시험)의 표기다. 시각 없이 만든 시험은 자정에 놓이므로 "오전 12:00"을 쓰지 않고 날짜만 쓴다.
    public static func date(_ date: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month().day().weekday()
        return date.formatted(hasTime(date, calendar: calendar) ? style.hour().minute() : style)
    }

    // 12시간제와 24시간제는 Mac의 시각 설정을 따른다. 그래서 기본값은 고정한 로케일이 아니라 지금 로케일이다.
    public static func clock(_ date: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
    }

    // 분 아래는 버려서 59분 59초 남으면 "59분 뒤"다.
    static func soon(_ date: Date, from now: Date) -> String? {
        let seconds = date.timeIntervalSince(now)
        let minutes = Int((abs(seconds) / 60).rounded(.down))
        guard minutes < soonMinutes else { return nil }
        if minutes == 0 { return String(localized: .dateTimeNow) }
        return seconds > 0 ? String(localized: .dateTimeMinutesLater(minutes)) : String(localized: .dateTimeMinutesAgo(minutes))
    }

    // 시험처럼 그날을 향해 세는 일정은 이 표기 대신 "D-3"으로 쓴다. 지난 날은 쓰지 않는다. 시험 표시는 지나면 사라지기 때문이다.
    public static func dday(days: Int) -> String {
        days == 0 ? String(localized: .ddayToday) : String(localized: .ddayDays(max(days, 0)))
    }
}
