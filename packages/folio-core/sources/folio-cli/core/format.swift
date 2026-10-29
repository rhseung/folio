import FolioDomain
import Foundation

/// `● 그래프 이론  EC4207 · 김교수`: the dot carries the course color, the name stays plain.
func courseHeader(_ c: CourseRef, catalog: Catalog?) {
    let people = c.course.instructorIds.compactMap { id in catalog?.people.first { $0.id == id }?.name }
    say("●".course(c.color) + " " + c.course.title.styled(.bold) + "  " + ([c.code] + people).joined(separator: " · ").styled(.dim))
}

/// Near dates read relative (`오늘`, `내일`, `D-7`), far ones as `11월 30일 (월)`; time follows the system's 12/24 hour.
func when(_ date: Date, now: Date, time: Bool = false, calendar: Calendar = .current) -> String {
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    let day = switch days {
    case 0: "오늘"
    case 1: "내일"
    case -1: "어제"
    case 2...14: "D-\(days)"
    default: date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: "ko_KR")))
    }
    // Exams and deadlines taken from all-day calendar events sit at midnight; "오전 12:00" there is noise, not a time.
    let text = time && date != calendar.startOfDay(for: date) ? "\(day) \(date.formatted(date: .omitted, time: .shortened))" : day
    return switch days {
    case ..<0: text.styled(.dim)
    case 0: text.styled(.red, .bold)
    case 1: text.styled(.yellow, .bold)
    case 2...3: text.styled(.yellow)
    default: text
    }
}

/// `6개 · --all로 취소된 것까지`.
func footer(_ count: Int, hidden: String? = nil) {
    say(([("\(count)개")] + (hidden.map { [$0] } ?? [])).joined(separator: " · ").styled(.dim))
}

/// For `--lines`: one item per line, the first field a ref other commands take (docs/SPEC.md "줄 형식").
func line(_ fields: [String]) { say(fields.map { $0.replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t")) }
