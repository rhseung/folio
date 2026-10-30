import FolioActions
import FolioDomain
import Foundation
import Observation

/// Takes the course's file from the view on each draw: the loaded course is a value the workspace replaces on every save.
@MainActor @Observable
final class CourseGradesModel {
    let workspace: Workspace
    let courseId: UUID
    var target = 90.0
    var editingEntry: ScoreEntry?
    var editingComponent: GradeComponent?
    var deletingComponent: GradeComponent?
    var deletingEntry: ScoreEntry?

    init(workspace: Workspace, course: UUID) {
        self.workspace = workspace
        courseId = course
    }

    func result(_ file: CourseFile) -> GradeCalculator.CourseScore { GradeCalculator.score(components: file.components, entries: file.scores) }

    func components(_ file: CourseFile) -> [GradeComponent] { file.components.sorted { $0.order < $1.order } }

    func lines(_ file: CourseFile) -> [GradeLine] { GradeLine.lines(components(file), scores: file.scores) }

    func subtitle(_ file: CourseFile) -> String {
        String(localized: .courseGradesSubtitle(file.course.gradingMode.label, file.components.count))
    }

    func componentsNote(_ file: CourseFile) -> String {
        let total = file.components.map(\.weight).reduce(0, +)
        return String(localized: .courseGradesWeightTotal(total.formatted()))
            + (file.components.isEmpty || total == 100 ? "" : String(localized: .courseGradesWeightNot100))
    }

    /// A relatively graded course is aimed at by place, with the A share standing in for a target score.
    func relative(_ file: CourseFile) -> Double? { file.course.gradingMode == .relative ? file.policy.effectiveTopGradeRatio : nil }

    func addComponent(_ file: CourseFile) {
        let order = (file.components.map(\.order).max() ?? -1) + 1
        editingComponent = GradeComponent(device: workspace.device, at: .now, name: "", weight: 10, order: order)
    }

    func componentDetail(_ c: GradeComponent, in file: CourseFile) -> String {
        let counted = file.scores.filter { $0.componentId == c.id && !$0.excused }.count
        return [c.aggregation.label, c.expectedCount.map { String(localized: .courseGradesCountOf(counted, $0)) }].compactMap { $0 }.joined(separator: " · ")
    }

    static func ratioText(_ ratio: Double?) -> String { ratio.map { "\(($0 * 100).formatted(.number.precision(.fractionLength(0))))%" } ?? "—" }

    func canAdd(_ c: GradeComponent) -> Bool { workspace.can(ScoreAdd(course: courseId, component: c.id, score: 0, max: 100)) }

    func addScore(_ c: GradeComponent) {
        editingEntry = ScoreEntry(device: workspace.device, at: .now, componentId: c.id, title: "", score: 0, max: 100)
    }

    func setExcused(_ entry: ScoreEntry, _ excused: Bool) {
        workspace.run(ScoreSet(course: courseId, score: entry.id, excused: .set(excused)))
    }

    /// Swaps a component with its neighbor and renumbers all, since imported components may share one `order`.
    func move(_ id: UUID, by delta: Int) { workspace.run(ComponentMove(course: courseId, component: id, by: delta)) }

    func remove(_ c: GradeComponent) { workspace.run(ComponentRemove(course: courseId, component: c.id)) }

    func remove(_ e: ScoreEntry) { workspace.run(ScoreRemove(course: courseId, score: e.id)) }

    static func removeTitle(_ c: GradeComponent) -> String { String(localized: .courseGradesRemoveComponentConfirm(c.name)) }

    static func removeMessage(_ c: GradeComponent, in file: CourseFile) -> String? {
        let scores = file.scores.filter { $0.componentId == c.id }.count
        return scores > 0 ? String(localized: .courseGradesRemoveComponentScores(scores)) : nil
    }

    static func removeTitle(_ e: ScoreEntry) -> String {
        e.title.isEmpty ? String(localized: .courseGradesRemoveScoreConfirm) : String(localized: .courseGradesRemoveNamedScoreConfirm(e.title))
    }

    // MARK: Attendance

    struct AttendanceSummary {
        let absences: Int
        let detail: String
        let ratio: Double?
        let cap: AttendanceCap?
        let next: AttendanceCap?
    }

    func attendance(_ file: CourseFile) -> AttendanceSummary {
        let policy = file.policy
        let absences = GradeCalculator.absences(in: file.heldAttendance(at: workspace.now), policy: policy)
        let detail = [policy.attendanceCap.isEmpty ? String(localized: .courseGradesNoCap) : capSummary(policy),
                      policy.latesPerAbsence.map { String(localized: .courseGradesLatesPerAbsence($0)) }].compactMap { $0 }.joined(separator: " · ")
        return AttendanceSummary(absences: absences, detail: detail, ratio: policy.minAttendanceRatio,
                          cap: GradeCalculator.attendanceCap(absences: absences, policy: policy),
                          next: GradeCalculator.nextCap(absences: absences, policy: policy))
    }

    func symbol(_ grade: UUID) -> String { workspace.catalog.grade(grade)?.symbol ?? "?" }

    func nextText(_ a: AttendanceSummary) -> String? {
        a.next.map { String(localized: .courseGradesNextCap($0.absences - a.absences, symbol($0.maxGrade))) }
    }

    func capSummary(_ policy: GradePolicy) -> String {
        policy.attendanceCap.sorted { $0.absences < $1.absences }
            .map { String(localized: .courseGradesCapItem($0.absences, symbol($0.maxGrade))) }
            .joined(separator: " · ")
    }

    func latePolicy(_ file: CourseFile) -> String? { file.policy.latePolicy.flatMap { $0.isEmpty ? nil : $0 } }

    /// What the remaining components must average for the target, as the panel words it.
    static func needText(_ need: Double?) -> String {
        need.map { $0 > 100 ? String(localized: .courseGradesNeedImpossible) : $0 <= 0 ? String(localized: .courseGradesNeedSecured)
            : String(localized: .courseGradesNeedPercent($0.oneDecimal)) } ?? String(localized: .courseGradesNeedNone)
    }
}

extension Aggregation {
    var label: String {
        switch self {
        case .sum: String(localized: .aggregationSum)
        case .mean: String(localized: .aggregationMean)
        case .single: String(localized: .aggregationSingle)
        case .dropLowest(let n): String(localized: .aggregationDropLowest(n))
        case .bestOf(let n): String(localized: .aggregationBestOf(n))
        }
    }
}

extension Double {
    /// A z score the way grades are talked about: `평균 +2.5σ`, `평균 -0.7σ`, or `평균` when it rounds to zero.
    var sigmas: String {
        let r = (self * 10).rounded() / 10
        return r == 0 ? String(localized: .courseGradesMean) : String(localized: .courseGradesSigmas(String(format: "%+.1f", r)))
    }

    /// A gap from the class mean in points, for a score whose standard deviation wasn't published: `평균 +8점`.
    var points: String {
        let r = (self * 10).rounded() / 10
        return r == 0 ? String(localized: .courseGradesMean) : String(localized: .courseGradesPointsGap((r > 0 ? "+" : "") + r.formatted()))
    }

    var percent: String { (self * 100).formatted(.number.precision(.fractionLength(0...1))) + "%" }
}
