import Charts
import FolioDomain
import SwiftUI

struct StudyTimeBlock: View {
    @State private var model: StudyTimeModel
    @State private var hovered: String?

    init(workspace: Workspace) {
        _model = State(initialValue: StudyTimeModel(workspace: workspace))
    }

    var body: some View {
        let chart = model.chart
        Block(String(localized: .todayStudyTitle), note: String(localized: .todayStudyNote)) {
            if model.bars.isEmpty {
                EmptyCard(symbol: "clock", title: String(localized: .todayStudyEmpty))
            } else {
                Card(padding: Theme.Space.xl) {
                    HStack(alignment: .top, spacing: Theme.Space.xxl) {
                        totals(chart).frame(width: 200, alignment: .leading)
                        Chart {
                        ForEach(chart.segments) { s in
                            BarMark(x: .value(String(localized: .todayStudyAxisDay), s.day), yStart: .value(String(localized: .todayStudyAxisStart), s.start),
                                    yEnd: .value(String(localized: .todayStudyAxisEnd), s.end), width: .ratio(0.5))
                                .foregroundStyle(by: .value(String(localized: .todayStudyAxisCourse), s.title))
                                .cornerRadius(Theme.Radius.small)
                                .opacity(hovered == nil || hovered == s.day ? 1 : 0.35)
                        }
                        if let hovered, let tip = model.tooltip(hovered, in: chart) {
                            RuleMark(x: .value(String(localized: .todayStudyAxisDay), hovered))
                                .foregroundStyle(Theme.Palette.line.opacity(0))
                                // Kept inside the plot: above it, the card's own border is drawn over the tooltip.
                                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                    tooltip(day: tip.day, total: tip.total, segments: tip.segments)
                                }
                        }
                    }
                    .chartXScale(domain: chart.days.map { StudyTimeModel.label($0, today: chart.today) })
                    .chartXSelection(value: $hovered)
                    .chartForegroundStyleScale(domain: chart.courses.map(\.title), range: chart.courses.map { model.workspace.accent($0.id).color })
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let day = value.as(String.self) {
                                    let today = day == StudyTimeModel.todayLabel
                                    Text(day).fontWeight(today ? .semibold : .regular)
                                        .foregroundStyle(today ? Theme.Palette.text : Theme.Palette.textTertiary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine().foregroundStyle(Theme.Palette.lineSoft)
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(model.axisLabel(v, inHours: chart.inHours)).foregroundStyle(Theme.Palette.textTertiary)
                                }
                            }
                        }
                    }
                        // The courses are named in the totals beside the chart, with their colors.
                        .chartLegend(.hidden)
                        .font(Theme.Typeface.caption)
                        .frame(height: 200)
                    }
                }
            }
        }
        // The day too: after the day boundary the bars must shift by a day even when nothing new was logged.
        .task(id: "\(StudyTracker.shared.revision) \(chart.today)") { await model.load() }
    }

    func totals(_ chart: StudyTimeModel.Chart) -> some View {
        let courses = model.perCourse(chart)
        let top = courses.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            Figure(StudyTimeModel.todayLabel, StudyTimeModel.duration(chart.perDay[chart.today] ?? 0))
            HStack(spacing: Theme.Space.xl) {
                Figure(String(localized: .todayStudyFortnight), StudyTimeModel.duration(chart.total), font: Theme.Typeface.figureSmall)
                Figure(String(localized: .todayStudyDays), String(localized: .todayStudyDayCount(chart.perDay.values.filter { $0 > 0 }.count)), font: Theme.Typeface.figureSmall)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ForEach(courses, id: \.course.id) { entry in
                    HStack(spacing: Theme.Space.s) {
                        Text(entry.course.title).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1).frame(width: 88, alignment: .leading)
                        Capsule().fill(Theme.Palette.fill)
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule().fill(model.workspace.accent(entry.course.id).color).frame(width: proxy.size.width * entry.seconds / top)
                                }
                            }
                            .frame(height: Theme.Space.tight)
                        Text(StudyTimeModel.duration(entry.seconds)).monospacedDigit().frame(minWidth: 40, alignment: .trailing)
                    }
                    .font(Theme.Typeface.caption)
                }
            }
        }
    }

    func tooltip(day: String, total: TimeInterval, segments: [StudyTimeModel.Segment]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("\(day) · \(StudyTimeModel.duration(total))").fontWeight(.semibold)
            ForEach(segments.reversed()) { s in
                HStack(spacing: Theme.Space.tight) {
                    CourseDot(color: model.workspace.accent(s.courseId).color, size: 8)
                    Text(s.title).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Text(StudyTimeModel.duration(s.seconds)).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .font(Theme.Typeface.caption)
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .frame(width: 200, alignment: .leading)
        .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.line))
    }
}

struct AttendanceWarnings: View {
    let model: TodayModel

    var body: some View {
        let warnings = model.attendanceWarnings
        if !warnings.isEmpty {
            Card {
                ForEach(Array(warnings.enumerated()), id: \.element.course.id) { i, w in
                    CardRow(last: i == warnings.count - 1) {
                        CourseMark(model.workspace, w.course.id)
                        Text(.todayAttendanceAbsences(w.course.title, w.absences))
                        Spacer()
                        Chip(model.capLabel(w.cap), tone: .warning)
                    }
                }
            }
        }
    }
}
