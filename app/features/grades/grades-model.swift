import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class GradesModel {
    let workspace: Workspace
    var target = 4.3
    /// Nil targets cumulative GPA; otherwise the program whose GPA is the goal.
    var targetProgram: UUID? { didSet { if targetProgram != oldValue { remainingCredits = nil } } }
    /// Typed by the user; nil uses what is still left toward graduation or the program.
    var remainingCredits: Double?
    var expanded: UUID?
    /// Picked grades for the what-if; a nil value means "ungraded" and differs from no pick.
    var expected: [UUID: UUID?] = [:]

    init(workspace: Workspace) { self.workspace = workspace }

    enum Series { case semester, cumulative }

    struct Point: Identifiable {
        var id: String { "\(series)-\(label)" }
        let label: String
        let series: Series
        let gpa: Double
        /// Credits behind a semester point, so its bar's width shows its weight in the cumulative GPA.
        var credits: Double = 0
        /// Comes from the picks in the simulation, not from recorded grades.
        var simulated = false
    }

    struct SemesterRow {
        let semester: Semester
        let summary: GPACalculator.Summary
        let members: [Course]
        let enrolled: Double
        let inProgress: Bool
    }

    var catalog: Catalog { workspace.catalog }
    var courses: [Course] { workspace.allCourseRecords }
    var semesters: [Semester] { workspace.transcript.semesters.sorted { $0.order < $1.order } }
    var programs: [StudentProgram] { workspace.transcript.graduation.programs }
    var cumulative: GPACalculator.Summary { GPACalculator.cumulative(semesters: semesters, courses: courses, catalog: catalog) }
    var maxPoints: Double { catalog.maxPoints }

    var subtitle: String { String(localized: .gradesSubtitle(catalog.maxPoints.formatted())) }

    var stats: [StatStrip.Item] {
        let cumulative = cumulative
        let current = workspace.currentSemester.map { GPACalculator.semester($0, courses: courses, catalog: catalog) }
        let currentCredits = workspace.currentSemester.map { s in courses.filter { $0.semesterId == s.id }.map(\.credits).reduce(0, +) }
        let major = GPACalculator.major(courses: courses, catalog: catalog)
        return [
            .init(title: String(localized: .gradesCumulativeGpa), value: Self.gpa(cumulative),
                  detail: String(localized: .gradesEffectiveCredits(cumulative.effectiveCredits.formatted())), sensitive: true),
        ] + (programs.isEmpty
            ? [.init(title: String(localized: .gradesMajorGpa), value: Self.gpa(major), detail: Self.credits(major.effectiveCredits), sensitive: true)]
            : programs.map { p in
                let s = GPACalculator.program(p.codeId, courses: courses, catalog: catalog)
                return .init(title: programGPA(p), value: Self.gpa(s), detail: Self.credits(s.effectiveCredits), sensitive: true)
            }) + [
            .init(title: String(localized: .gradesTotalCredits), value: cumulative.totalCredits.formatted(),
                  detail: String(localized: .gradesTotalCreditsDetail)),
            .init(title: workspace.currentSemester?.title ?? String(localized: .gradesThisSemester), value: currentCredits.map(Self.credits) ?? "-",
                  detail: current?.gpa == nil ? String(localized: .gradesInProgress) : Self.gpa(current!), sensitive: current?.gpa != nil),
        ]
    }

    func programGPA(_ p: StudentProgram) -> String { String(localized: .gradesProgramGpa(p.title(in: catalog))) }

    // MARK: Goal

    var goal: GPACalculator.Summary {
        targetProgram.map { GPACalculator.program($0, courses: courses, catalog: catalog) } ?? cumulative
    }

    /// Ungraded courses are still to be graded, so the default counts them as remaining.
    var remainingDefault: Double {
        targetProgram.map { GPACalculator.programRemaining($0, courses: courses, catalog: catalog) }
            ?? max(0, workspace.transcript.graduation.totalCredits
                - GPACalculator.graduation(semesters: semesters, courses: courses, catalog: workspace.requirementCatalog).counted)
    }

    var remaining: Double {
        get { remainingCredits ?? remainingDefault }
        set { remainingCredits = newValue }
    }

    var targetOptions: [(UUID?, String)] {
        [(UUID?.none, String(localized: .gradesCumulativeGpa))] + programs.map { (Optional($0.codeId), programGPA($0)) }
    }

    var goalNow: String { String(localized: .gradesGoalNow(Self.gpa(goal))) }

    var remainingDetail: String {
        String(localized: targetProgram == nil ? .gradesGoalRemainingGraduation : .gradesGoalRemainingProgram)
    }

    var need: Double? { GPACalculator.requiredAverage(target: target, current: goal, remainingCredits: remaining) }
    var unreachable: Bool { (need ?? 0) > catalog.maxPoints }
    var needText: String { need.map { $0.formatted(.number.precision(.fractionLength(3))) } ?? "-" }
    var needDetail: String? { unreachable ? String(localized: .gradesGoalUnreachable(catalog.maxPoints.formatted())) : nil }

    // MARK: Semesters

    var semesterRows: [SemesterRow] {
        semesters.reversed().map { s in
            let sum = GPACalculator.semester(s, courses: courses, catalog: catalog)
            let members = courses.filter { $0.semesterId == s.id }.sorted { $0.title < $1.title }
            // A semester in progress has no graded credits yet; show what is being taken instead of 0.
            let enrolled = members.map(\.credits).reduce(0, +)
            return SemesterRow(semester: s, summary: sum, members: members, enrolled: enrolled,
                               inProgress: sum.gpa == nil && sum.totalCredits == 0 && enrolled > 0)
        }
    }

    func toggle(_ semester: UUID) { expanded = expanded == semester ? nil : semester }

    // MARK: Simulation

    var currentMembers: [Course] {
        workspace.currentSemester.map { s in courses.filter { $0.semesterId == s.id }.sorted { $0.title < $1.title } } ?? []
    }

    func pick(_ course: Course) -> UUID? { expected[course.id] ?? course.finalGrade }

    // `.some` keeps a picked "미정": assigning plain nil would remove the pick instead.
    func setPick(_ grade: UUID?, for course: Course) { expected[course.id] = .some(grade) }

    func resetPicks() { expected = [:] }

    func courseDetail(_ c: Course) -> String { String(localized: .gradesSimulationCourseDetail(c.credits.formatted(), c.gradingMode.label)) }

    var simulatedTerm: GPACalculator.Summary? {
        workspace.currentSemester.map { GPACalculator.semester($0, courses: GPACalculator.simulate(expected, courses: courses), catalog: catalog) }
    }

    var simulatedTermDetail: String? {
        simulatedTerm.map {
            $0.effectiveCredits > 0 ? String(localized: .gradesEffectiveCredits($0.effectiveCredits.formatted()))
                : String(localized: .gradesSimulationPickToCompute)
        }
    }

    var simulatedTotal: GPACalculator.Summary {
        GPACalculator.cumulative(semesters: semesters, courses: GPACalculator.simulate(expected, courses: courses), catalog: catalog)
    }

    /// The change the picks make to the cumulative GPA, nil when it rounds away.
    var simulatedChange: Double? {
        guard let now = cumulative.gpa, let then = simulatedTotal.gpa, abs(then - now) >= 0.0005 else { return nil }
        return then - now
    }

    // MARK: Trend

    /// With picks in the simulation, points those picks change are swapped for simulated ones.
    var points: [Point] {
        let recorded = Self.points(GPACalculator.trend(semesters: semesters, courses: courses, catalog: catalog))
        guard !expected.isEmpty else { return recorded }
        let known = Dictionary(keepingFirst: recorded.map { ($0.id, $0.gpa) })
        return Self.points(GPACalculator.trend(semesters: semesters, courses: GPACalculator.simulate(expected, courses: courses), catalog: catalog)).map { p in
            var p = p
            p.simulated = known[p.id].map { abs($0 - p.gpa) >= 0.0005 } ?? true
            return p
        }
    }

    static func points(_ trend: [GPATrendPoint]) -> [Point] {
        trend.flatMap { t in
            let label = t.semester.shortTitle
            return [Point(label: label, series: .semester, gpa: t.gpa, credits: t.credits)]
                + (t.cumulative.map { [Point(label: label, series: .cumulative, gpa: $0)] } ?? [])
        }
    }

    /// Bars start at a floor below the lowest value, not 0, so 3.8 against 4.3 is still readable.
    static func floor(_ points: [Point]) -> Double { max(0, ((points.map(\.gpa).min() ?? 3.5) * 2).rounded(.down) / 2 - 0.5) }

    /// The dashed line starts at the last recorded point so the what-if reads as a continuation.
    static func dashed(_ cumulative: [Point]) -> [Point] {
        cumulative.firstIndex(where: \.simulated).map { Array(cumulative[max(0, $0 - 1)...]) } ?? []
    }

    /// Hovered values go in the legend, not a tooltip in the plot, which always covered some of the marks.
    static func legendValue(_ points: [Point], series: Series, at label: String?) -> String {
        guard let p = points.first(where: { $0.label == label && $0.series == series }) else { return "" }
        return [GPACalculator.label(p.gpa), p.credits > 0 ? "· " + credits(p.credits) : nil, p.simulated ? String(localized: .gradesTrendExpected) : nil]
            .compactMap { $0 }.joined(separator: " ")
    }

    static func gpa(_ s: GPACalculator.Summary) -> String { GPACalculator.label(s.gpa) }

    static func credits(_ n: Double) -> String { String(localized: .gradesCredits(n.formatted())) }
}

extension Semester {
    /// The title is data from the domain; only its trailing word is dropped for the chart's axis.
    var shortTitle: String { title.replacingOccurrences(of: "학기", with: "") }
}
