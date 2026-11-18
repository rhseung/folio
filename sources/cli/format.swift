import FolioDomain
import Foundation

func courseHeader(_ c: CourseRef, catalog: Catalog?) {
    let people = c.course.instructorIds.compactMap { id in catalog?.people.first { $0.id == id }?.name }
    say("●".course(c.color) + " " + c.course.title.styled(.bold) + "  " + ([c.code] + people).joined(separator: " · ").styled(.dim))
}

// 어느 날인지는 앱과 같은 `RelativeDate.day`로 쓴다. 하루 경계 전의 새벽에는 그 밤의 마감이 아직 "오늘"이다.
func when(_ date: Date, now: Date, time: Bool = false, calendar: Calendar = .current, settings: Settings = Settings()) -> String {
    let ko = Locale(identifier: "ko_KR")
    let days = RelativeDate.days(date, from: now, settings: settings, calendar: calendar)
    let day = RelativeDate.day(date, from: now, settings: settings, calendar: calendar, short: true, locale: ko)
    let text =
        time && RelativeDate.hasTime(date, calendar: calendar) ? day + " " + RelativeDate.time(date, calendar: calendar, locale: ko) : day
    return switch days {
    case ..<0: text.styled(.dim)
    case 0: text.styled(.red, .bold)
    case 1: text.styled(.yellow, .bold)
    case 2...max(settings.urgency.examUrgentDays, 2): text.styled(.yellow)
    default: text
    }
}

func footer(_ count: Int, hidden: String? = nil) {
    say(([String(localized: .commonCount(count))] + (hidden.map { [$0] } ?? [])).joined(separator: " · ").styled(.dim))
}

func line(_ fields: [String]) { say(fields.map { $0.replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t")) }
