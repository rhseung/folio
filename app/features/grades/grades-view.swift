import Charts
import FolioDomain
import SwiftUI

struct GradesView: View {
    @State private var model: GradesModel
    @State private var hovered: String?

    init(workspace: Workspace) {
        _model = State(initialValue: GradesModel(workspace: workspace))
    }

    var body: some View {
        let cumulative = model.cumulative

        Page {
            PageHeader(title: String(localized: .gradesTitle), subtitle: model.subtitle)

            StatStrip(items: model.stats)

            HStack(alignment: .top, spacing: Theme.Space.l + 2) {
                Block(String(localized: .gradesTrend)) {
                    Card(padding: Theme.Space.l) {
                        trend(model.points)
                    }
                    .sensitive(.block)
                }
                .frame(maxWidth: .infinity)

                Block(String(localized: .gradesGoal)) {
                    Card {
                        if !model.programs.isEmpty {
                            FormRow(label: String(localized: .gradesGoalTarget), detail: model.goalNow) {
                                ChoiceMenu(selection: $model.targetProgram, options: model.targetOptions)
                            }
                        }
                        FormRow(label: String(localized: .gradesGoalGpa)) { ScrubField(value: $model.target, range: 0...model.maxPoints, step: 0.01, fractionLength: 2, width: 96) }
                        FormRow(label: String(localized: .gradesGoalRemaining), detail: model.remainingDetail) {
                            ScrubField(value: $model.remaining, range: 0...200, step: 1, width: 96)
                        }
                        FormRow(label: String(localized: .gradesGoalNeed), detail: model.needDetail, last: true) {
                            Text(model.needText).rolling(model.needText)
                                .font(Theme.Typeface.figureSmall)
                                .foregroundStyle(model.unreachable ? Theme.Palette.danger : Theme.Palette.text)
                        }
                    }
                    .sensitive(.block)
                }
                .frame(width: 320)
            }

            Block(String(localized: .gradesBySemester)) {
                Card {
                    CardRow {
                        Text(.gradesColumnSemester).frame(maxWidth: .infinity, alignment: .leading)
                        column(String(localized: .gradesColumnCredits), muted: true)
                        column(String(localized: .gradesColumnEffective), muted: true)
                        column("GPA", muted: true)
                    }
                    .font(Theme.Typeface.label)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    ForEach(model.semesterRows, id: \.semester.id) { row in
                        let s = row.semester, sum = row.summary, inProgress = row.inProgress
                        let open = model.expanded == s.id
                        let toggle = { withAnimation(.snappy(duration: 0.2)) { model.toggle(s.id) } }
                        Button(action: toggle) {
                            CardRow {
                                HStack(spacing: Theme.Space.s) {
                                    Image(systemName: "chevron.right")
                                        .font(Theme.Glyph.small)
                                        .foregroundStyle(Theme.Palette.textTertiary)
                                        .rotationEffect(.degrees(open ? 90 : 0))
                                    Text(s.title).fontWeight(.semibold)
                                    if inProgress { Chip(String(localized: .gradesEnrolled)) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                column(inProgress ? row.enrolled.formatted() : sum.totalCredits.formatted(), muted: inProgress)
                                column(inProgress ? "-" : sum.effectiveCredits.formatted(), muted: inProgress)
                                column(GradesModel.gpa(sum), strong: true, muted: inProgress)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.pointing(.plain))
                        .contextMenu { Button(open ? .gradesCollapseCourses : .gradesShowCourses, action: toggle).disabled(row.members.isEmpty) }
                        if open {
                            ForEach(row.members) { c in
                                let grade = model.catalog.grade(c.finalGrade)
                                CardRow {
                                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                        Text(c.title)
                                        Text(c.gradingMode.label).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                    }
                                    .padding(.leading, Theme.Space.l + 2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    column(c.credits.formatted(), muted: true)
                                    column(grade?.countsInGpa == true ? c.credits.formatted() : "-", muted: true)
                                    column(grade?.symbol ?? String(localized: .gradesInProgress), strong: grade != nil, muted: grade == nil)
                                }
                                .transition(.opacity)
                            }
                        }
                    }
                    CardRow(last: true) {
                        Text(.gradesCumulative).frame(maxWidth: .infinity, alignment: .leading)
                        column(cumulative.totalCredits.formatted())
                        column(cumulative.effectiveCredits.formatted())
                        column(GradesModel.gpa(cumulative))
                    }
                    .font(Theme.Typeface.bodyStrong)
                }
                .sensitive(.block)
            }

            // The record first, then the what-if: picks here redraw the trend above as a dashed continuation.
            simulation(cumulative: cumulative)
        }
        .navigationTitle(.gradesTitle)
        #if DEBUG && os(macOS)
        .onAppear { if SnapshotDriver.directory != nil { model.expanded = model.semesters.first { $0.year == 2026 && $0.term == .spring }?.id } }
        #endif
    }

    func simulation(cumulative: GPACalculator.Summary) -> some View {
        let members = model.currentMembers
        let term = model.simulatedTerm
        let total = model.simulatedTotal
        return Block(title: String(localized: .gradesSimulation), note: model.workspace.currentSemester?.title, trailing: {
            if !model.expected.isEmpty { Button(.gradesSimulationReset) { model.resetPicks() }.buttonStyle(.ghost) }
        }) {
            Card {
                if members.isEmpty { CardRow { EmptyLine(String(localized: .gradesSimulationEmpty)) } }
                ForEach(members) { c in
                    let pick = Binding(get: { model.pick(c) }, set: { model.setPick($0, for: c) })
                    let grades = model.catalog.grades(for: c.gradingMode)
                    FormRow(label: c.title, detail: model.courseDetail(c)) {
                        GradeSteps(selection: pick, grades: grades.map { ($0.id, $0.symbol, $0.points != nil) })
                    }
                    .contextMenu {
                        Picker(String(localized: .gradesSimulationExpectedGrade), selection: pick) {
                            ForEach(grades) { Text($0.symbol).tag(Optional($0.id)) }
                            Text(.gradesSimulationUndecided).tag(UUID?.none)
                        }
                        .pickerStyle(.inline)
                        if !model.expected.isEmpty {
                            Divider()
                            Button(.gradesSimulationResetAll) { model.resetPicks() }
                        }
                    }
                }
                FormRow(label: String(localized: .gradesSimulationTermGpa), detail: model.simulatedTermDetail) {
                    Text(term.map(GradesModel.gpa) ?? "-").font(Theme.Typeface.figureSmall).rolling(term.map(GradesModel.gpa) ?? "-")
                }
                FormRow(label: String(localized: .gradesSimulationCumulativeGpa), detail: String(localized: .gradesGoalNow(GradesModel.gpa(cumulative))), last: true) {
                    HStack(spacing: Theme.Space.s) {
                        if let change = model.simulatedChange {
                            Text(String(format: "%+.3f", change))
                                .font(Theme.Typeface.caption)
                                .foregroundStyle(change > 0 ? Theme.Palette.success : Theme.Palette.danger)
                        }
                        Text(GradesModel.gpa(total)).font(Theme.Typeface.figureSmall).rolling(GradesModel.gpa(total))
                    }
                }
            }
            .sensitive(.block)
        }
    }

    /// Semester GPA as bars as wide as their credits and the running cumulative GPA as a line: same scale, so one axis, told apart by mark and hue.
    /// Values show on hover; a fixed label on the line sat over the bars and read as a bar's value.
    func trend(_ points: [GradesModel.Point]) -> some View {
        let semester = points.filter { $0.series == .semester }
        let cumulative = points.filter { $0.series == .cumulative }
        let low = GradesModel.floor(points)
        // Equal bars made a 3-credit summer look as heavy as an 18-credit term; width follows credits instead.
        let widest = semester.map(\.credits).max() ?? 0
        func width(_ p: GradesModel.Point) -> MarkDimension { .ratio(widest > 0 ? max(0.08, 0.6 * p.credits / widest) : 0.4) }
        func value(_ series: GradesModel.Series) -> some View {
            Text(GradesModel.legendValue(points, series: series, at: hovered))
                .monospacedDigit().fontWeight(.semibold).foregroundStyle(Theme.Palette.text)
        }
        let solid = cumulative.filter { !$0.simulated }
        let dashed = GradesModel.dashed(cumulative)
        let termLabel = String(localized: .gradesColumnSemester)
        let lineLabel = String(localized: .gradesTrendSeries)
        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(spacing: Theme.Space.l) {
                HStack(spacing: Theme.Space.tight) {
                    RoundedRectangle(cornerRadius: Theme.Radius.mark).fill(Theme.Series.one).frame(width: 10, height: 10)
                    Text(.gradesTrendSemesterGpa)
                    value(.semester)
                }
                HStack(spacing: Theme.Space.tight) {
                    ZStack { Capsule().fill(Theme.Series.oneCompanion).frame(width: 16, height: 2); Circle().fill(Theme.Series.oneCompanion).frame(width: 8, height: 8) }
                    Text(.gradesCumulativeGpa)
                    value(.cumulative)
                }
                if !dashed.isEmpty {
                    HStack(spacing: Theme.Space.tight) {
                        RoundedRectangle(cornerRadius: Theme.Radius.mark).fill(Theme.Series.one.opacity(0.4)).frame(width: 10, height: 10)
                        Text(.gradesTrendSimulated)
                    }
                }
                Spacer()
                if let hovered { Text(hovered).fontWeight(.semibold).foregroundStyle(Theme.Palette.text) }
            }
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.textSecondary)

            Chart {
                ForEach(semester) { p in
                    // Fades toward the floor so the bar reads by its top edge, not as a solid block.
                    let c = Theme.Series.one.opacity((hovered == nil || hovered == p.label ? 1 : 0.45) * (p.simulated ? 0.4 : 1))
                    // An opaque base under the fade, or the cumulative fill shows through half of the end bars.
                    BarMark(x: .value(termLabel, p.label), yStart: .value("GPA", low), yEnd: .value("GPA", p.gpa), width: width(p))
                        .foregroundStyle(Theme.Palette.card)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                    BarMark(x: .value(termLabel, p.label), yStart: .value("GPA", low), yEnd: .value("GPA", p.gpa), width: width(p))
                        .foregroundStyle(LinearGradient(colors: [c, c.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                }
                ForEach(solid) { p in
                    AreaMark(x: .value(termLabel, p.label), yStart: .value("GPA", low), yEnd: .value("GPA", p.gpa), series: .value(lineLabel, "recorded"))
                        .foregroundStyle(LinearGradient(colors: [Theme.Series.oneCompanion.opacity(0.18), Theme.Series.oneCompanion.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                        .zIndex(-1)
                    LineMark(x: .value(termLabel, p.label), y: .value("GPA", p.gpa), series: .value(lineLabel, "recorded"))
                        .foregroundStyle(Theme.Series.oneCompanion)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                ForEach(dashed) { p in
                    LineMark(x: .value(termLabel, p.label), y: .value("GPA", p.gpa), series: .value(lineLabel, "simulated"))
                        .foregroundStyle(Theme.Series.oneCompanion)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                }
                ForEach(cumulative) { p in
                    PointMark(x: .value(termLabel, p.label), y: .value("GPA", p.gpa))
                        .symbol {
                            Circle().fill(p.simulated ? Theme.Palette.card : Theme.Series.oneCompanion).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(p.simulated ? Theme.Series.oneCompanion : Theme.Palette.card, lineWidth: 2))
                        }
                }
                if let hovered {
                    RuleMark(x: .value(termLabel, hovered))
                        .foregroundStyle(Theme.Palette.line)
                        .zIndex(-1)
                }
            }
            .chartYScale(domain: low...model.maxPoints)
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(stride(from: low, through: model.maxPoints, by: 0.5))) {
                    AxisGridLine().foregroundStyle(Theme.Palette.lineSoft)
                    AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(Theme.Palette.textTertiary) } }
            .chartXSelection(value: $hovered)
            .frame(height: 220)
        }
    }

    /// A right-aligned number column, shared by the header, semester and course rows so they line up.
    func column(_ text: String, strong: Bool = false, muted: Bool = false) -> some View {
        Text(text)
            .fontWeight(strong ? .semibold : nil)
            .foregroundStyle(muted ? Theme.Palette.textTertiary : Theme.Palette.text)
            .monospacedDigit()
            .frame(width: 64, alignment: .trailing)
    }
}
