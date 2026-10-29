import Charts
import FolioDomain
import SwiftUI

/// "최근 2주 과목별 공부 시간": stacked bars per study day in the course colors.
struct StudyTimeBlock: View {
    @Environment(Workspace.self) private var workspace
    @State private var bars: [Workspace.StudyBar] = []
    @State private var hovered: String?
    static let days = 14

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

    var body: some View {
        let today = workspace.today
        let days = (0..<Self.days).map { today.adding(days: $0 - Self.days + 1) }
        let courses = workspace.currentCourses.filter { c in bars.contains { $0.courseId == c.id } }
        let total = bars.map(\.seconds).reduce(0, +)
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
        Block("최근 2주 공부 시간", note: bars.isEmpty ? nil : "합계 \(Self.duration(total))") {
            Card(padding: Theme.Space.l) {
                if bars.isEmpty {
                    EmptyLine("아직 기록된 공부 시간이 없습니다")
                } else {
                    Chart {
                        ForEach(segments) { s in
                            BarMark(x: .value("날짜", s.day), yStart: .value("시작", s.start), yEnd: .value("끝", s.end), width: .ratio(0.5))
                                .foregroundStyle(by: .value("과목", s.title))
                                .cornerRadius(Theme.Radius.small)
                                .opacity(hovered == nil || hovered == s.day ? 1 : 0.35)
                        }
                        if let hovered, let seconds = perDay.first(where: { Self.label($0.key, today: today) == hovered })?.value {
                            RuleMark(x: .value("날짜", hovered))
                                .foregroundStyle(Theme.Palette.line.opacity(0))
                                // Kept inside the plot: above it, the card's own border is drawn over the tooltip.
                                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                    let date = days.first { Self.label($0, today: today) == hovered }
                                    tooltip(day: date.map { $0 == today ? "오늘" : "\($0.month)월 \($0.day)일" } ?? hovered,
                                            total: seconds, segments: segments.filter { $0.day == hovered })
                                }
                        }
                    }
                    .chartXScale(domain: days.map { Self.label($0, today: today) })
                    .chartXSelection(value: $hovered)
                    .chartForegroundStyleScale(domain: courses.map(\.title), range: courses.map { workspace.accent($0.id).color })
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let day = value.as(String.self) {
                                    Text(day).fontWeight(day == "오늘" ? .semibold : .regular)
                                        .foregroundStyle(day == "오늘" ? Theme.Palette.text : Theme.Palette.textTertiary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine().foregroundStyle(Theme.Palette.lineSoft)
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(v == 0 ? "0" : inHours ? "\(v.formatted())시간" : "\(Int(v))분").foregroundStyle(Theme.Palette.textTertiary)
                                }
                            }
                        }
                    }
                    .chartLegend(position: .bottom, alignment: .leading, spacing: Theme.Space.m)
                    .font(Theme.Typeface.caption)
                    .frame(height: 180)
                }
            }
        }
        // The day too: after the day boundary the bars must shift by a day even when nothing new was logged.
        .task(id: "\(StudyTracker.shared.revision) \(today)") { bars = await workspace.recentStudyTime(days: Self.days, now: .now) }
    }

    func tooltip(day: String, total: TimeInterval, segments: [Segment]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("\(day) · \(Self.duration(total))").fontWeight(.semibold)
            ForEach(segments.reversed()) { s in
                HStack(spacing: Theme.Space.tight) {
                    CourseDot(color: workspace.accent(s.courseId).color, size: 8)
                    Text(s.title).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Text(Self.duration(s.seconds)).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .font(Theme.Typeface.caption)
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .frame(width: 200, alignment: .leading)
        .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.line))
    }

    /// The day of the month, with its month on the 1st; today is named.
    static func label(_ day: LocalDate, today: LocalDate) -> String {
        day == today ? "오늘" : day.day == 1 ? "\(day.month)/1" : "\(day.day)"
    }

    static func duration(_ seconds: TimeInterval) -> String { StudyTime.label(seconds) }
}

/// Courses one absence away from an attendance cap (docs/SPEC.md "알림"), shown on the today screen.
struct AttendanceWarnings: View {
    @Environment(Workspace.self) private var workspace

    var body: some View {
        let warnings = workspace.currentCourses.compactMap { course in
            course.file.capOneAway(at: .now).map { (course, $0.absences, $0.cap) }
        }
        if !warnings.isEmpty {
            Card {
                ForEach(Array(warnings.enumerated()), id: \.element.0.id) { i, w in
                    CardRow(last: i == warnings.count - 1) {
                        CourseDot(color: workspace.accent(w.0.id).color)
                        Text("\(w.0.title) · 결석 \(w.1)회")
                        Spacer()
                        Chip("한 번 더 결석하면 최대 \(workspace.catalog.grade(w.2.maxGrade)?.symbol ?? "상한")", tone: .warning)
                    }
                }
            }
        }
    }
}
