import FolioCore
import Foundation

// 날짜를 지금에 견줘 말로 쓰는 규칙은 여기 하나에 둔다. 날 수는 달력 날짜가 아니라 공부일(하루 경계)로 센다.
// 하루 안의 남은 때는 시각으로 센다. 그래서 새벽 3시 마감은 하루 경계 전이라도 "3시간 뒤"이고, 하루가 넘으면 공부일로 센다.
public enum RelativeDate {
    public static let week = 7
    public static let month = 30

    // 종일 일정의 자정을 공부일로 바꾸면 하루 경계 앞이라 전날이 된다. 그래서 시각이 없는 날짜는 달력 날짜 그대로 센다.
    public static func days(_ date: Date, from now: Date, settings: Settings, calendar: Calendar) -> Int {
        let day = hasTime(date, calendar: calendar) ? settings.studyDay(of: date, calendar: calendar) : LocalDate(date, in: calendar)
        return settings.studyDay(of: now, calendar: calendar).days(until: day)
    }

    // 종일 일정에서 가져온 마감과 시험은 자정에 놓인다. 그 자정은 시각이 아니므로 시간으로 세지 않고 날로 센다.
    public static func hasTime(_ date: Date, calendar: Calendar) -> Bool { date != calendar.startOfDay(for: date) }

    // 남은 때나 지난 때. 시각이 있고 하루 안이면 시간이나 분으로, 그보다 멀면 날, 주, 달로 센다.
    public static func distance(_ date: Date, from now: Date, settings: Settings, calendar: Calendar) -> String {
        (hasTime(date, calendar: calendar) ? within(date, from: now) : nil)
            ?? distance(days: days(date, from: now, settings: settings, calendar: calendar))
    }

    // 하루 차이는 "1일 뒤"가 아니라 "내일", "어제"다. 7일부터는 주, 30일부터는 달로 세고 단위보다 작은 나머지는 버린다.
    // 13일은 "1주 뒤"이고, 달은 달력의 길이와 상관없이 30일이다.
    public static func distance(days: Int) -> String {
        let later = days > 0
        let count = abs(days)
        switch count {
        case 0: return String(localized: .relativeDayToday)
        case 1: return later ? String(localized: .relativeDayTomorrow) : String(localized: .relativeDayYesterday)
        case ..<week: return later ? String(localized: .relativeDayLater(count)) : String(localized: .relativeDayAgo(count))
        case ..<month:
            return later ? String(localized: .relativeDayWeeksLater(count / week)) : String(localized: .relativeDayWeeksAgo(count / week))
        default:
            return later
                ? String(localized: .relativeDayMonthsLater(count / month)) : String(localized: .relativeDayMonthsAgo(count / month))
        }
    }

    // 하루 안의 때를 시간으로, 한 시간 안이면 분으로 쓴다. 하루를 넘으면 nil이다. 단위보다 작은 나머지는 버려서,
    // 59분 남으면 "59분 뒤"이지 "1시간 뒤"가 아니다.
    public static func within(_ date: Date, from now: Date) -> String? {
        let seconds = date.timeIntervalSince(now)
        let minutes = Int((abs(seconds) / 60).rounded(.down))
        guard minutes < 24 * 60 else { return nil }
        let later = seconds > 0
        if minutes >= 60 {
            let hours = minutes / 60
            return later ? String(localized: .relativeTimeHoursLater(hours)) : String(localized: .relativeTimeHoursAgo(hours))
        }
        if minutes == 0 { return String(localized: .relativeTimeNow) }
        return later ? String(localized: .relativeTimeMinutesLater(minutes)) : String(localized: .relativeTimeMinutesAgo(minutes))
    }

    // 시험처럼 그날을 향해 세는 일정은 "D-3"으로 쓴다. 지난 날은 쓰지 않는다. 시험 표시는 지나면 사라지기 때문이다.
    public static func dday(days: Int) -> String {
        days == 0 ? String(localized: .ddayToday) : String(localized: .ddayDays(max(days, 0)))
    }

    // 어느 날인지. 오늘, 내일, 어제이고, 일주일 안이면 요일, 그보다 멀면 "12/2(수)"다. 주나 달로 세면 요일만으로는
    // 어느 날인지 알 수 없어서 날짜를 쓴다.
    public static func day(
        _ date: Date, from now: Date, settings: Settings, calendar: Calendar, short: Bool = false, locale: Locale = .autoupdatingCurrent
    ) -> String {
        let days = days(date, from: now, settings: settings, calendar: calendar)
        switch abs(days) {
        case ...1: return distance(days: days)
        case ..<week:
            var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            style = style.weekday(short ? .abbreviated : .wide)
            return date.formatted(style)
        default: return CourseFile.day(date, calendar: calendar)
        }
    }

    public static func time(_ date: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
    }

    // 한 줄에 쓰는 마감. 하루 안이면 남은 때만 쓰고, 내일이나 어제면 몇 시인지가 중요해서 시각을 붙인다.
    // 그보다 멀면 날 수만 쓴다.
    public static func line(_ date: Date, from now: Date, settings: Settings, calendar: Calendar, locale: Locale = .autoupdatingCurrent)
        -> String
    {
        let timed = hasTime(date, calendar: calendar)
        if timed, let near = within(date, from: now) { return near }
        let days = days(date, from: now, settings: settings, calendar: calendar)
        let text = distance(days: days)
        return timed && abs(days) <= 1 ? text + " " + time(date, calendar: calendar, locale: locale) : text
    }
}
