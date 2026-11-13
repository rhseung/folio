import FolioActions
import FolioDomain
import Foundation
import Observation

// 불러온 과목은 저장할 때마다 workspace가 바꾸는 값이므로, 그릴 때마다 뷰에서 과목 파일을 받는다.
@MainActor @Observable
final class CourseGradesModel {
    let workspace: Workspace
    let courseId: UUID
    var target = 90.0
    var editingEntry: ScoreEntry?
    var editingComponent: GradeComponent?
    var pending: PendingAction?

    init(workspace: Workspace, course: UUID) {
        self.workspace = workspace
        courseId = course
    }

    func result(_ file: CourseFile) -> GradeCalculator.CourseScore {
        GradeCalculator.score(components: file.components, entries: file.scores)
    }

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

    func relative(_ file: CourseFile) -> Double? { file.course.gradingMode == .relative ? file.policy.effectiveTopGradeRatio : nil }

    func addComponent(_ file: CourseFile) {
        let order = (file.components.map(\.order).max() ?? -1) + 1
        editingComponent = GradeComponent(device: workspace.device, at: .now, name: "", weight: 10, order: order)
    }

    func componentDetail(_ c: GradeComponent, in file: CourseFile) -> String {
        let counted = file.scores.filter { $0.componentId == c.id && !$0.excused }.count
        return [c.aggregation.label, c.expectedCount.map { String(localized: .courseGradesCountOf(counted, $0)) }].compactMap { $0 }.joined(
            separator: " · ")
    }

    static func ratioText(_ ratio: Double?) -> String {
        ratio.map { "\(($0 * 100).formatted(.number.precision(.fractionLength(0))))%" } ?? "—"
    }

    func canAdd(_ c: GradeComponent) -> Bool { workspace.can(ScoreAdd(course: courseId, component: c.id, score: 0, max: 100)) }

    func addScore(_ c: GradeComponent) {
        editingEntry = ScoreEntry(device: workspace.device, at: .now, componentId: c.id, title: "", score: 0, max: 100)
    }

    func setExcused(_ entry: ScoreEntry, _ excused: Bool) {
        workspace.run(ScoreSet(course: courseId, score: entry.id, excused: .set(excused)))
    }

    // 가져온 구성 요소는 `order`가 겹칠 수 있으므로, 이웃과 바꾼 뒤 모두 번호를 다시 매긴다.
    func move(_ id: UUID, by delta: Int) { workspace.run(ComponentMove(course: courseId, component: id, by: delta)) }

    func remove(_ c: GradeComponent) { pending = workspace.ask(ComponentRemove(course: courseId, component: c.id)) }

    func remove(_ e: ScoreEntry) { pending = workspace.ask(ScoreRemove(course: courseId, score: e.id)) }

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
        let detail = [
            policy.attendanceCap.isEmpty ? String(localized: .courseGradesNoCap) : capSummary(policy),
            policy.latesPerAbsence.map { String(localized: .courseGradesLatesPerAbsence($0)) },
        ].compactMap { $0 }.joined(separator: " · ")
        return AttendanceSummary(
            absences: absences, detail: detail, ratio: policy.minAttendanceRatio,
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

    static func needText(_ need: Double?) -> String {
        need.map {
            $0 > 100
                ? String(localized: .courseGradesNeedImpossible)
                : $0 <= 0
                    ? String(localized: .courseGradesNeedSecured)
                    : String(localized: .courseGradesNeedPercent($0.oneDecimal))
        } ?? String(localized: .courseGradesNeedNone)
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
    var sigmas: String {
        let r = (self * 10).rounded() / 10
        return r == 0 ? String(localized: .courseGradesMean) : String(localized: .courseGradesSigmas(String(format: "%+.1f", r)))
    }

    var points: String {
        let r = (self * 10).rounded() / 10
        return r == 0 ? String(localized: .courseGradesMean) : String(localized: .courseGradesPointsGap((r > 0 ? "+" : "") + r.formatted()))
    }

    var percent: String { (self * 100).formatted(.number.precision(.fractionLength(0...1))) + "%" }
}
