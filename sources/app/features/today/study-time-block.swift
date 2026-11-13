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
                    Fold(wideFrom: 480, spacing: Theme.Space.xxl, stackSpacing: Theme.Space.xl) {
                        totals(chart).frame(width: 200, alignment: .leading)
                        Chart {
                            ForEach(chart.segments) { s in
                                BarMark(
                                    x: .value(String(localized: .todayStudyAxisDay), s.day),
                                    yStart: .value(String(localized: .todayStudyAxisStart), s.start),
                                    yEnd: .value(String(localized: .todayStudyAxisEnd), s.end), width: .ratio(0.5)
                                )
                                .foregroundStyle(by: .value(String(localized: .todayStudyAxisCourse), s.title))
                                .cornerRadius(Theme.Radius.small)
                                .opacity(hovered == nil || hovered == s.day ? 1 : 0.35)
                            }
                            if let hovered, let tip = model.tooltip(hovered, in: chart) {
                                RuleMark(x: .value(String(localized: .todayStudyAxisDay), hovered))
                                    .foregroundStyle(Theme.Palette.line.opacity(0))
                                    // 도표 위에 두면 카드 테두리가 도움말 위에 그려지므로 도표 안에 둔다.
                                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                        tooltip(day: tip.day, total: tip.total, segments: tip.segments)
                                    }
                            }
                        }
                        .chartXScale(domain: chart.days.map { StudyTimeModel.label($0, today: chart.today) })
                        .chartXSelection(value: $hovered)
                        .chartForegroundStyleScale(
                            domain: chart.courses.map(\.title), range: chart.courses.map { model.workspace.accent($0.id).color }
                        )
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
                        .chartLegend(.hidden)
                        .font(Theme.Typeface.caption)
                        .frame(height: 200)
                    }
                }
            }
        }
        // 하루 경계가 지나면 새 기록이 없어도 막대가 하루 옮겨 가야 하므로 날짜도 키에 넣는다.
        .task(id: "\(StudyTracker.shared.revision) \(chart.today)") { await model.load() }
    }

    func totals(_ chart: StudyTimeModel.Chart) -> some View {
        let courses = model.perCourse(chart)
        let top = courses.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            Figure(StudyTimeModel.todayLabel, StudyTimeModel.duration(chart.perDay[chart.today] ?? 0))
            HStack(spacing: Theme.Space.xl) {
                Figure(String(localized: .todayStudyFortnight), StudyTimeModel.duration(chart.total), font: Theme.Typeface.figureSmall)
                Figure(
                    String(localized: .todayStudyDays), String(localized: .todayStudyDayCount(chart.perDay.values.filter { $0 > 0 }.count)),
                    font: Theme.Typeface.figureSmall)
            }
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.s, verticalSpacing: Theme.Space.s) {
                ForEach(courses, id: \.course.id) { entry in
                    GridRow {
                        Text(entry.course.title).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1).frame(
                            width: 88, alignment: .leading)
                        Capsule().fill(Theme.Palette.fill)
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule().fill(model.workspace.accent(entry.course.id).color).frame(
                                        width: proxy.size.width * entry.seconds / top)
                                }
                            }
                            .frame(height: Theme.Space.tight)
                        Text(StudyTimeModel.duration(entry.seconds)).monospacedDigit().lineLimit(1).fixedSize()
                            .gridColumnAlignment(.trailing)
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
                    CourseDot(color: model.workspace.accent(s.courseId).color)
                    Text(s.title).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Text(StudyTimeModel.duration(s.seconds)).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary).fixedSize()
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
