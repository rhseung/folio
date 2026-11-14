import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class GradesModel {
    let workspace: Workspace
    var target = 4.3
    var targetProgram: UUID? { didSet { if targetProgram != oldValue { remainingCredits = nil } } }
    var remainingCredits: Double?
    var expanded: UUID?
    // nil 값은 "미정"을 뜻하며 고르지 않은 것과 다르다.
    var expected: [UUID: UUID?] = [:]

    init(workspace: Workspace) { self.workspace = workspace }

    enum Series { case semester, cumulative }

    struct Point: Identifiable {
        var id: String { "\(series)-\(label)" }
        let label: String
        let series: Series
        let gpa: Double
        var credits: Double = 0
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
    var courses: [Course] { workspace.allCourses }
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
            .init(
                title: String(localized: .gradesCumulativeGpa), value: Self.gpa(cumulative),
                detail: String(localized: .gradesEffectiveCredits(cumulative.effectiveCredits.formatted())), sensitive: true)
        ]
            + (programs.isEmpty
                ? [
                    .init(
                        title: String(localized: .gradesMajorGpa), value: Self.gpa(major), detail: Self.credits(major.effectiveCredits),
                        sensitive: true)
                ]
                : programs.map { p in
                    let s = GPACalculator.program(p.codeId, courses: courses, catalog: catalog)
                    return .init(title: programGPA(p), value: Self.gpa(s), detail: Self.credits(s.effectiveCredits), sensitive: true)
                }) + [
                .init(
                    title: String(localized: .gradesTotalCredits), value: cumulative.totalCredits.formatted(),
                    detail: String(localized: .gradesTotalCreditsDetail)),
                .init(
                    title: workspace.currentSemester?.title ?? String(localized: .gradesThisSemester),
                    value: currentCredits.map(Self.credits) ?? "-",
                    detail: current?.gpa == nil ? String(localized: .gradesInProgress) : Self.gpa(current!), sensitive: current?.gpa != nil),
            ]
    }

    func programGPA(_ p: StudentProgram) -> String { String(localized: .gradesProgramGpa(p.title(in: catalog))) }

    // MARK: Goal

    var goal: GPACalculator.Summary {
        targetProgram.map { GPACalculator.program($0, courses: courses, catalog: catalog) } ?? cumulative
    }

    var remainingDefault: Double {
        targetProgram.map { GPACalculator.programRemaining($0, courses: courses, catalog: catalog) }
            ?? max(
                0,
                workspace.transcript.graduation.totalCredits
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
            let enrolled = members.map(\.credits).reduce(0, +)
            return SemesterRow(
                semester: s, summary: sum, members: members, enrolled: enrolled,
                inProgress: s.term != .credited && sum.gpa == nil && sum.totalCredits == 0 && enrolled > 0)
        }
    }

    func toggle(_ semester: UUID) { expanded = expanded == semester ? nil : semester }

    // MARK: Simulation

    var currentMembers: [Course] {
        workspace.currentSemester.map { s in courses.filter { $0.semesterId == s.id }.sorted { $0.title < $1.title } } ?? []
    }

    func pick(_ course: Course) -> UUID? { expected[course.id] ?? course.finalGrade }

    // `.some`으로 넣어야 고른 "미정"이 남는다. 그냥 nil을 넣으면 고른 것이 지워진다.
    func setPick(_ grade: UUID?, for course: Course) { expected[course.id] = .some(grade) }

    func resetPicks() { expected = [:] }

    func courseDetail(_ c: Course) -> String {
        String(localized: .gradesSimulationCourseDetail(c.credits.formatted(), c.gradingMode.label))
    }

    var simulatedTerm: GPACalculator.Summary? {
        workspace.currentSemester.map {
            GPACalculator.semester($0, courses: GPACalculator.simulate(expected, courses: courses), catalog: catalog)
        }
    }

    var simulatedTermDetail: String? {
        simulatedTerm.map {
            $0.effectiveCredits > 0
                ? String(localized: .gradesEffectiveCredits($0.effectiveCredits.formatted()))
                : String(localized: .gradesSimulationPickToCompute)
        }
    }

    var simulatedTotal: GPACalculator.Summary {
        GPACalculator.cumulative(semesters: semesters, courses: GPACalculator.simulate(expected, courses: courses), catalog: catalog)
    }

    var simulatedChange: Double? {
        guard let now = cumulative.gpa, let then = simulatedTotal.gpa, abs(then - now) >= 0.0005 else { return nil }
        return then - now
    }

    // MARK: Trend

    var points: [Point] {
        let recorded = Self.points(GPACalculator.trend(semesters: semesters, courses: courses, catalog: catalog))
        guard !expected.isEmpty else { return recorded }
        let known = Dictionary(keepingFirst: recorded.map { ($0.id, $0.gpa) })
        return Self.points(
            GPACalculator.trend(semesters: semesters, courses: GPACalculator.simulate(expected, courses: courses), catalog: catalog)
        ).map { p in
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

    static func floor(_ points: [Point]) -> Double { max(0, ((points.map(\.gpa).min() ?? 3.5) * 2).rounded(.down) / 2 - 0.5) }

    static func dashed(_ cumulative: [Point]) -> [Point] {
        cumulative.firstIndex(where: \.simulated).map { Array(cumulative[max(0, $0 - 1)...]) } ?? []
    }

    static func legendValue(_ points: [Point], series: Series, at label: String?) -> String {
        guard let p = points.first(where: { $0.label == label && $0.series == series }) else { return "" }
        return [
            GPACalculator.label(p.gpa), p.credits > 0 ? "· " + credits(p.credits) : nil,
            p.simulated ? String(localized: .gradesTrendExpected) : nil,
        ]
        .compactMap { $0 }.joined(separator: " ")
    }

    static func gpa(_ s: GPACalculator.Summary) -> String { GPACalculator.label(s.gpa) }

    static func credits(_ n: Double) -> String { String(localized: .gradesCredits(n.formatted())) }
}

extension Semester {
    var shortTitle: String { title.replacingOccurrences(of: "학기", with: "") }
}
