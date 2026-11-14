import FolioDomain
import Foundation

func courseHeader(_ c: CourseRef, catalog: Catalog?) {
    let people = c.course.instructorIds.compactMap { id in catalog?.people.first { $0.id == id }?.name }
    say("●".course(c.color) + " " + c.course.title.styled(.bold) + "  " + ([c.code] + people).joined(separator: " · ").styled(.dim))
}

func when(_ date: Date, now: Date, time: Bool = false, calendar: Calendar = .current) -> String {
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    let day =
        switch days {
        case 0: String(localized: .whenToday)
        case 1: String(localized: .whenTomorrow)
        case -1: String(localized: .whenYesterday)
        case 2...14: "D-\(days)"
        default: date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: "ko_KR")))
        }
    // 종일 일정에서 가져온 시험과 마감은 자정에 있으므로, 거기서 `오전 12:00`은 시각이 아니다.
    let text = time && date != calendar.startOfDay(for: date) ? "\(day) \(date.formatted(date: .omitted, time: .shortened))" : day
    return switch days {
    case ..<0: text.styled(.dim)
    case 0: text.styled(.red, .bold)
    case 1: text.styled(.yellow, .bold)
    case 2...3: text.styled(.yellow)
    default: text
    }
}

func footer(_ count: Int, hidden: String? = nil) {
    say(([String(localized: .commonCount(count))] + (hidden.map { [$0] } ?? [])).joined(separator: " · ").styled(.dim))
}

func line(_ fields: [String]) { say(fields.map { $0.replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t")) }
