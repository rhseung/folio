import Charts
import FolioDomain
import SwiftUI

/// Credits and GPA per semester, cumulative and major GPA, the trend, and the average needed for a target.
struct GradesView: View {
    @Environment(Workspace.self) private var workspace
    @State private var target = 4.3
    /// Nil targets cumulative GPA; otherwise the program whose GPA is the goal.
    @State private var targetProgram: UUID?
    /// Typed by the user; nil uses what is still left toward graduation or the program.
    @State private var remainingCredits: Double?
    @State private var expanded: UUID?
    /// Picked grades for the what-if; a nil value means "ungraded" and differs from no pick.
    @State private var expected: [UUID: UUID?] = [:]
    @State private var hovered: String?

    struct Point: Identifiable {
        var id: String { "\(series)-\(label)" }
        let label: String
        let series: String
        let gpa: Double
        /// Credits behind a semester point, so its bar's width shows its weight in the cumulative GPA.
        var credits: Double = 0
        /// Comes from the picks in "이번 학기 시뮬레이션", not from recorded grades.
        var simulated = false
    }

    var body: some View {
        let catalog = workspace.catalog
        let courses = workspace.allCourseRecords
        let semesters = workspace.transcript.semesters.sorted { $0.order < $1.order }
        let cumulative = GPACalculator.cumulative(semesters: semesters, courses: courses, catalog: catalog)
        let major = GPACalculator.major(courses: courses, catalog: catalog)
        let programs = workspace.transcript.graduation.programs
        let rule = workspace.transcript.graduation
        let progress = GPACalculator.graduation(semesters: semesters, courses: courses, catalog: workspace.requirementCatalog)
        let goal = targetProgram.map { GPACalculator.program($0, courses: courses, catalog: catalog) } ?? cumulative
        // Ungraded courses are still to be graded, so the default counts them as remaining.
        let leftDefault = targetProgram.map { GPACalculator.programRemaining($0, courses: courses, catalog: catalog) }
            ?? max(0, rule.totalCredits - progress.counted)
        let current = workspace.currentSemester.map { GPACalculator.semester($0, courses: courses, catalog: catalog) }
        let currentCredits = workspace.currentSemester.map { s in courses.filter { $0.semesterId == s.id }.map(\.credits).reduce(0, +) }

        Page {
            PageHeader(title: "성적", subtitle: "\(catalog.maxPoints.formatted()) 만점")

            StatStrip(items: [
                .init(title: "누적 GPA", value: gpa(cumulative), detail: "유효 \(cumulative.effectiveCredits.formatted())학점", sensitive: true),
            ] + (programs.isEmpty ? [.init(title: "전공 GPA", value: gpa(major), detail: "\(major.effectiveCredits.formatted())학점", sensitive: true)] : programs.map { p in
                let s = GPACalculator.program(p.codeId, courses: courses, catalog: catalog)
                return .init(title: "\(workspace.programTitle(p)) GPA", value: gpa(s), detail: "\(s.effectiveCredits.formatted())학점", sensitive: true)
            }) + [
                .init(title: "총 학점", value: cumulative.totalCredits.formatted(), detail: "인정학기 포함"),
                .init(title: workspace.currentSemester?.title ?? "이번 학기", value: currentCredits.map { "\($0.formatted())학점" } ?? "-",
                      detail: current?.gpa == nil ? "진행 중" : gpa(current!), sensitive: current?.gpa != nil),
            ])

            HStack(alignment: .top, spacing: Theme.Space.l + 2) {
                Block("GPA 추이") {
                    Card(padding: Theme.Space.l) {
                        trend(points(semesters: semesters, courses: courses, catalog: catalog))
                    }
                    .sensitive(.block)
                }
                .frame(maxWidth: .infinity)

                Block("목표 역산") {
                    Card {
                        if !programs.isEmpty {
                            FormRow(label: "대상", detail: "지금 \(gpa(goal))") {
                                ChoiceMenu(selection: $targetProgram, options: [(UUID?.none, "누적 GPA")] + programs.map { (Optional($0.codeId), "\(workspace.programTitle($0)) GPA") })
                            }
                        }
                        FormRow(label: "목표 GPA") { ScrubField(value: $target, range: 0...catalog.maxPoints, step: 0.01, fractionLength: 2, width: 96) }
                        FormRow(label: "남은 학점", detail: (targetProgram == nil ? "졸업까지" : "과정 요건까지") + ", 수강 중 포함") {
                            ScrubField(value: Binding(get: { remainingCredits ?? leftDefault }, set: { remainingCredits = $0 }), range: 0...200, step: 1, width: 96)
                        }
                        let need = GPACalculator.requiredAverage(target: target, current: goal, remainingCredits: remainingCredits ?? leftDefault)
                        FormRow(label: "남은 학기 평균", detail: (need ?? 0) > catalog.maxPoints ? "만점 \(catalog.maxPoints.formatted())보다 높아 닿을 수 없습니다" : nil, last: true) {
                            let needText = need.map { $0.formatted(.number.precision(.fractionLength(3))) } ?? "-"
                            Text(needText).rolling(needText)
                                .font(Theme.Typeface.figureSmall)
                                .foregroundStyle((need ?? 0) > catalog.maxPoints ? Theme.Palette.danger : Theme.Palette.text)
                        }
                    }
                    .sensitive(.block)
                }
                .frame(width: 320)
            }

            Block("학기별") {
                Card {
                    CardRow {
                        Text("학기").frame(maxWidth: .infinity, alignment: .leading)
                        column("학점", muted: true)
                        column("유효", muted: true)
                        column("GPA", muted: true)
                    }
                    .font(Theme.Typeface.label)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    ForEach(semesters.reversed(), id: \.id) { s in
                        let sum = GPACalculator.semester(s, courses: courses, catalog: catalog)
                        let members = courses.filter { $0.semesterId == s.id }.sorted { $0.title < $1.title }
                        // A semester in progress has no graded credits yet; show what is being taken instead of 0.
                        let enrolled = members.map(\.credits).reduce(0, +)
                        let inProgress = sum.gpa == nil && sum.totalCredits == 0 && enrolled > 0
                        let open = expanded == s.id
                        let toggle = { withAnimation(.snappy(duration: 0.2)) { expanded = open ? nil : s.id } }
                        Button(action: toggle) {
                            CardRow {
                                HStack(spacing: Theme.Space.s) {
                                    Image(systemName: "chevron.right")
                                        .font(Theme.Glyph.small)
                                        .foregroundStyle(Theme.Palette.textTertiary)
                                        .rotationEffect(.degrees(open ? 90 : 0))
                                    Text(s.title).fontWeight(.semibold)
                                    if inProgress { Chip("수강 중") }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                column(inProgress ? enrolled.formatted() : sum.totalCredits.formatted(), muted: inProgress)
                                column(inProgress ? "-" : sum.effectiveCredits.formatted(), muted: inProgress)
                                column(gpa(sum), strong: true, muted: inProgress)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.pointing(.plain))
                        .contextMenu { Button(open ? "과목 접기" : "과목 보기", action: toggle).disabled(members.isEmpty) }
                        if open {
                            ForEach(members) { c in
                                let grade = catalog.grade(c.finalGrade)
                                CardRow {
                                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                        Text(c.title)
                                        Text(c.gradingMode.label).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                    }
                                    .padding(.leading, Theme.Space.l + 2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    column(c.credits.formatted(), muted: true)
                                    column(grade?.countsInGpa == true ? c.credits.formatted() : "-", muted: true)
                                    column(grade?.symbol ?? "진행 중", strong: grade != nil, muted: grade == nil)
                                }
                                .transition(.opacity)
                            }
                        }
                    }
                    CardRow(last: true) {
                        Text("누적").frame(maxWidth: .infinity, alignment: .leading)
                        column(cumulative.totalCredits.formatted())
                        column(cumulative.effectiveCredits.formatted())
                        column(gpa(cumulative))
                    }
                    .font(Theme.Typeface.bodyStrong)
                }
                .sensitive(.block)
            }

            // The record first, then the what-if: picks here redraw the trend above as a dashed continuation.
            simulation(semesters: semesters, courses: courses, catalog: catalog, cumulative: cumulative)
        }
        .navigationTitle("성적")
        .onChange(of: targetProgram) { remainingCredits = nil }
        #if DEBUG && os(macOS)
        .onAppear { if SnapshotDriver.directory != nil { expanded = workspace.transcript.semesters.first { $0.year == 2026 && $0.term == .spring }?.id } }
        #endif
    }

    func simulation(semesters: [Semester], courses: [Course], catalog: Catalog, cumulative: GPACalculator.Summary) -> some View {
        let semester = workspace.currentSemester
        let members = semester.map { s in courses.filter { $0.semesterId == s.id }.sorted { $0.title < $1.title } } ?? []
        let simulated = GPACalculator.simulate(expected, courses: courses)
        let term = semester.map { GPACalculator.semester($0, courses: simulated, catalog: catalog) }
        let total = GPACalculator.cumulative(semesters: semesters, courses: simulated, catalog: catalog)
        return Block(title: "이번 학기 시뮬레이션", note: semester?.title, trailing: {
            if !expected.isEmpty { Button("되돌리기") { expected = [:] }.buttonStyle(.ghost) }
        }) {
            Card {
                if members.isEmpty { CardRow { EmptyLine("이번 학기 과목이 없습니다") } }
                ForEach(members) { c in
                    let pick = Binding(
                        get: { expected[c.id] ?? c.finalGrade },
                        // `.some` keeps a picked "미정": assigning plain nil would remove the pick instead.
                        set: { expected[c.id] = .some($0) }
                    )
                    let grades = catalog.grades(for: c.gradingMode)
                    FormRow(label: c.title, detail: "\(c.credits.formatted())학점 · \(c.gradingMode.label)") {
                        GradeSteps(selection: pick, grades: grades.map { ($0.id, $0.symbol, $0.points != nil) })
                    }
                    .contextMenu {
                        Picker("예상 성적", selection: pick) {
                            ForEach(grades) { Text($0.symbol).tag(Optional($0.id)) }
                            Text("미정").tag(UUID?.none)
                        }
                        .pickerStyle(.inline)
                        if !expected.isEmpty {
                            Divider()
                            Button("모두 되돌리기") { expected = [:] }
                        }
                    }
                }
                FormRow(label: "예상 학기 GPA", detail: term.map { $0.effectiveCredits > 0 ? "유효 \($0.effectiveCredits.formatted())학점" : "성적을 고르면 계산합니다" }) {
                    Text(term.map(gpa) ?? "-").font(Theme.Typeface.figureSmall).rolling(term.map(gpa) ?? "-")
                }
                FormRow(label: "예상 누적 GPA", detail: "지금 \(gpa(cumulative))", last: true) {
                    HStack(spacing: Theme.Space.s) {
                        if let now = cumulative.gpa, let then = total.gpa, abs(then - now) >= 0.0005 {
                            Text(String(format: "%+.3f", then - now))
                                .font(Theme.Typeface.caption)
                                .foregroundStyle(then > now ? Theme.Palette.success : Theme.Palette.danger)
                        }
                        Text(gpa(total)).font(Theme.Typeface.figureSmall).rolling(gpa(total))
                    }
                }
            }
            .sensitive(.block)
        }
    }

    /// Semester GPA and the cumulative GPA after each semester, skipping the credited one and those without a GPA.
    /// Semester GPA as bars as wide as their credits and the running cumulative GPA as a line: same scale, so one axis, told apart by mark and hue.
    /// Values show on hover; a fixed label on the line sat over the bars and read as a bar's value.
    func trend(_ points: [Point]) -> some View {
        let semester = points.filter { $0.series == "학기" }
        let cumulative = points.filter { $0.series == "누적" }
        // Bars start at a floor below the lowest value, not 0, so 3.8 against 4.3 is still readable.
        let low = max(0, ((points.map(\.gpa).min() ?? 3.5) * 2).rounded(.down) / 2 - 0.5)
        let byLabel = Dictionary(grouping: points, by: \.label)
        // Equal bars made a 3-credit summer look as heavy as an 18-credit term; width follows credits instead.
        let widest = semester.map(\.credits).max() ?? 0
        func width(_ p: Point) -> MarkDimension { .ratio(widest > 0 ? max(0.08, 0.6 * p.credits / widest) : 0.4) }
        // Hovered values go in the legend, not a tooltip in the plot, which always covered some of the marks.
        func value(_ series: String) -> some View {
            let p = hovered.flatMap { byLabel[$0] }?.first { $0.series == series }
            return Text(p.map { GPACalculator.label($0.gpa) + ($0.credits > 0 ? " · \($0.credits.formatted())학점" : "") + ($0.simulated ? " 예상" : "") } ?? "")
                .monospacedDigit().fontWeight(.semibold).foregroundStyle(Theme.Palette.text)
        }
        let solid = cumulative.filter { !$0.simulated }
        // The dashed line starts at the last recorded point so the what-if reads as a continuation.
        let dashed = cumulative.firstIndex(where: \.simulated).map { Array(cumulative[max(0, $0 - 1)...]) } ?? []
        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(spacing: Theme.Space.l) {
                HStack(spacing: Theme.Space.tight) {
                    RoundedRectangle(cornerRadius: Theme.Radius.mark).fill(Theme.Series.one).frame(width: 10, height: 10)
                    Text("학기 GPA")
                    value("학기")
                }
                HStack(spacing: Theme.Space.tight) {
                    ZStack { Capsule().fill(Theme.Series.oneCompanion).frame(width: 16, height: 2); Circle().fill(Theme.Series.oneCompanion).frame(width: 8, height: 8) }
                    Text("누적 GPA")
                    value("누적")
                }
                if !dashed.isEmpty {
                    HStack(spacing: Theme.Space.tight) {
                        RoundedRectangle(cornerRadius: Theme.Radius.mark).fill(Theme.Series.one.opacity(0.4)).frame(width: 10, height: 10)
                        Text("예상 (시뮬레이션)")
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
                    BarMark(x: .value("학기", p.label), yStart: .value("GPA", low), yEnd: .value("GPA", p.gpa), width: width(p))
                        .foregroundStyle(Theme.Palette.card)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                    BarMark(x: .value("학기", p.label), yStart: .value("GPA", low), yEnd: .value("GPA", p.gpa), width: width(p))
                        .foregroundStyle(LinearGradient(colors: [c, c.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                }
                ForEach(solid) { p in
                    AreaMark(x: .value("학기", p.label), yStart: .value("GPA", low), yEnd: .value("GPA", p.gpa), series: .value("선", "누적"))
                        .foregroundStyle(LinearGradient(colors: [Theme.Series.oneCompanion.opacity(0.18), Theme.Series.oneCompanion.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                        .zIndex(-1)
                    LineMark(x: .value("학기", p.label), y: .value("GPA", p.gpa), series: .value("선", "누적"))
                        .foregroundStyle(Theme.Series.oneCompanion)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                ForEach(dashed) { p in
                    LineMark(x: .value("학기", p.label), y: .value("GPA", p.gpa), series: .value("선", "예상"))
                        .foregroundStyle(Theme.Series.oneCompanion)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                }
                ForEach(cumulative) { p in
                    PointMark(x: .value("학기", p.label), y: .value("GPA", p.gpa))
                        .symbol {
                            Circle().fill(p.simulated ? Theme.Palette.card : Theme.Series.oneCompanion).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(p.simulated ? Theme.Series.oneCompanion : Theme.Palette.card, lineWidth: 2))
                        }
                }
                if let hovered {
                    RuleMark(x: .value("학기", hovered))
                        .foregroundStyle(Theme.Palette.line)
                        .zIndex(-1)
                }
            }
            .chartYScale(domain: low...workspace.catalog.maxPoints)
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(stride(from: low, through: workspace.catalog.maxPoints, by: 0.5))) {
                    AxisGridLine().foregroundStyle(Theme.Palette.lineSoft)
                    AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(Theme.Palette.textTertiary) } }
            .chartXSelection(value: $hovered)
            .frame(height: 220)
        }
    }

    /// With picks in the simulation, points those picks change are swapped for simulated ones.
    func points(semesters: [Semester], courses: [Course], catalog: Catalog) -> [Point] {
        let recorded = Self.points(semesters: semesters, courses: courses, catalog: catalog)
        guard !expected.isEmpty else { return recorded }
        let known = Dictionary(keepingFirst: recorded.map { ($0.id, $0.gpa) })
        return Self.points(semesters: semesters, courses: GPACalculator.simulate(expected, courses: courses), catalog: catalog).map { p in
            var p = p
            p.simulated = known[p.id].map { abs($0 - p.gpa) >= 0.0005 } ?? true
            return p
        }
    }

    static func points(semesters: [Semester], courses: [Course], catalog: Catalog) -> [Point] {
        var result: [Point] = []
        for (i, s) in semesters.enumerated() where s.term != .credited {
            let summary = GPACalculator.semester(s, courses: courses, catalog: catalog)
            guard let g = summary.gpa else { continue }
            let label = s.shortTitle
            result.append(Point(label: label, series: "학기", gpa: g, credits: summary.effectiveCredits))
            if let c = GPACalculator.cumulative(semesters: Array(semesters[...i]), courses: courses, catalog: catalog).gpa {
                result.append(Point(label: label, series: "누적", gpa: c))
            }
        }
        return result
    }

    /// A right-aligned number column, shared by the header, semester and course rows so they line up.
    func column(_ text: String, strong: Bool = false, muted: Bool = false) -> some View {
        Text(text)
            .fontWeight(strong ? .semibold : nil)
            .foregroundStyle(muted ? Theme.Palette.textTertiary : Theme.Palette.text)
            .monospacedDigit()
            .frame(width: 64, alignment: .trailing)
    }

    func gpa(_ s: GPACalculator.Summary) -> String {
        GPACalculator.label(s.gpa)
    }
}

extension Semester {
    /// `2026 봄` for chart axes.
    var shortTitle: String { title.replacingOccurrences(of: "학기", with: "") }
}
