import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class StudyTimeModel {
    let workspace: Workspace
    var bars: [Bar] = []
    static let days = 14

    init(workspace: Workspace) { self.workspace = workspace }

    struct Bar: Identifiable, Sendable {
        var id: String { "\(day)-\(courseId)" }
        var day: LocalDate
        var courseId: UUID
        var seconds: TimeInterval
    }

    /// One course's part of a day's bar, already stacked: `start` and `end` in the chart's unit.
    struct Segment: Identifiable {
        var id: String { "\(day)-\(courseId)" }
        let day: String
        let courseId: UUID
        let title: String
        let seconds: TimeInterval
        let start: Double
        let end: Double
    }

    struct Chart {
        var today: LocalDate
        var days: [LocalDate]
        /// Only the courses with time logged, in the term's order, so the legend lists no empty course.
        var courses: [LoadedCourse]
        var total: TimeInterval
        var perDay: [LocalDate: TimeInterval]
        var inHours: Bool
        var segments: [Segment]
    }

    var chart: Chart {
        let today = workspace.today
        let days = (0..<Self.days).map { today.adding(days: $0 - Self.days + 1) }
        let courses = workspace.currentCourses.filter { c in bars.contains { $0.courseId == c.id } }
        let perDay = Dictionary(grouping: bars, by: \.day).mapValues { $0.map(\.seconds).reduce(0, +) }
        // Minutes until a day passes two hours, so a light fortnight reads 10분, 20분 rather than 0.15h.
        let inHours = (perDay.values.max() ?? 0) >= 2 * 3600
        let unit: Double = inHours ? 3600 : 60
        let top = (perDay.values.max() ?? 0) / unit
        // A sliver of card between stacked courses, so neighbouring colors don't run together.
        let gap = top * 0.012
        let segments = days.flatMap { day -> [Segment] in
            var y = 0.0
            return courses.compactMap { c in
                guard let bar = bars.first(where: { $0.day == day && $0.courseId == c.id }), bar.seconds > 0 else { return nil }
                let h = bar.seconds / unit
                defer { y += h }
                return Segment(day: Self.label(day, today: today), courseId: c.id, title: c.title, seconds: bar.seconds,
                               start: y == 0 ? 0 : y + gap, end: y + h)
            }
        }
        return Chart(today: today, days: days, courses: courses, total: bars.map(\.seconds).reduce(0, +), perDay: perDay,
                     inHours: inHours, segments: segments)
    }

    /// The hovered column's title and total, or nil when nothing was logged that day.
    func tooltip(_ hovered: String, in chart: Chart) -> (day: String, total: TimeInterval, segments: [Segment])? {
        guard let seconds = chart.perDay.first(where: { Self.label($0.key, today: chart.today) == hovered })?.value else { return nil }
        let date = chart.days.first { Self.label($0, today: chart.today) == hovered }
        let day = date.map { $0 == chart.today ? Self.todayLabel : String(localized: .todayStudyDate($0.month, $0.day)) } ?? hovered
        return (day, seconds, chart.segments.filter { $0.day == hovered })
    }

    func axisLabel(_ value: Double, inHours: Bool) -> String {
        value == 0 ? "0" : inHours ? String(localized: .todayStudyHours(value.formatted())) : String(localized: .todayStudyMinutes(Int(value)))
    }

    func load() async {
        let now = Date.now
        let stores = workspace.currentCourses.map { ($0.id, $0.store) }
        let settings = workspace.settings, calendar = workspace.calendar
        let first = settings.studyDay(of: now, calendar: calendar).adding(days: -(Self.days - 1))
        bars = await Task.detached {
            stores.flatMap { id, store in
                let sessions = ((try? store.log.readAll()) ?? []).events(StudySessionEvent.self).map(\.event)
                return StudyTime.perDay(sessions, settings: settings, calendar: calendar)
                    .filter { $0.key >= first }
                    .map { Bar(day: $0.key, courseId: id, seconds: $0.value) }
            }
        }.value
    }

    static var todayLabel: String { String(localized: .todayStudyToday) }

    static func label(_ day: LocalDate, today: LocalDate) -> String {
        day == today ? todayLabel : day.day == 1 ? "\(day.month)/1" : "\(day.day)"
    }

    static func duration(_ seconds: TimeInterval) -> String { StudyTime.label(seconds) }
}
