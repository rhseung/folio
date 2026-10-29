import FolioActions
import FolioDomain
import Foundation
import Observation

/// Numbers are kept as typed text so a half-typed value (`8.`) stays in the field instead of snapping back.
@MainActor @Observable
final class ScoreEntryModel {
    let workspace: Workspace
    let course: LoadedCourse
    let entry: ScoreEntry
    let isNew: Bool
    var componentId: UUID
    var title: String
    var score: String
    var max: String
    var mean: String
    var stdDev: String
    var excused: Bool

    init(workspace: Workspace, course: LoadedCourse, entry: ScoreEntry) {
        self.workspace = workspace
        self.course = course
        self.entry = entry
        isNew = !course.file.scores.contains { $0.id == entry.id }
        componentId = entry.componentId
        title = entry.title
        score = isNew ? "" : entry.score.formatted(.number.grouping(.never))
        max = entry.max.formatted(.number.grouping(.never))
        mean = entry.mean?.formatted(.number.grouping(.never)) ?? ""
        stdDev = entry.stdDev?.formatted(.number.grouping(.never)) ?? ""
        excused = entry.excused
    }

    var sheetTitle: String { String(localized: isNew ? .scoreSheetAdd : .scoreSheetEdit) }
    var confirmTitle: String { String(localized: isNew ? .commonAdd : .commonSave) }

    var valid: Bool {
        Double(score) != nil && (Double(max) ?? 0) > 0 && (mean.isEmpty || Double(mean) != nil) && (stdDev.isEmpty || Double(stdDev) != nil)
    }

    /// A single score is one by definition, so it needs no title of its own.
    var hasTitle: Bool { course.file.components.first { $0.id == componentId }?.aggregation != .single }

    var componentOptions: [(UUID, String)] { course.file.components.sorted { $0.order < $1.order }.map { ($0.id, $0.name) } }

    var meanDetail: String {
        let s = Double(score)
        let z = s.flatMap { s in Double(mean).flatMap { mu in Double(stdDev).flatMap { $0 > 0 ? (s - mu) / $0 : nil } } }
        let gap = s.flatMap { s in Double(mean).map { s - $0 } }
        return z.map(\.sigmas) ?? gap.map { String(localized: .scoreSheetGapNoStdDev($0.points)) } ?? String(localized: .scoreSheetMeanHint)
    }

    /// False when the action was refused, so the sheet stays open.
    func confirm() -> Bool {
        guard let s = Double(score), let m = Double(max) else { return false }
        let saved = isNew
            ? workspace.run(ScoreAdd(id: entry.id, course: course.id, component: componentId, title: title, score: s, max: m,
                                     mean: Double(mean), stdDev: Double(stdDev), date: entry.date, exam: entry.examId, assignment: entry.assignmentId,
                                     excused: excused))
            : workspace.run(ScoreSet(course: course.id, score: entry.id, component: .set(componentId), title: .set(title), value: .set(s), max: .set(m),
                                     mean: .set(Double(mean)), stdDev: .set(Double(stdDev)), excused: .set(excused)))
        return saved != nil
    }

    func remove() { workspace.run(ScoreRemove(course: course.id, score: entry.id)) }
}

@MainActor @Observable
final class ComponentModel {
    let workspace: Workspace
    let course: LoadedCourse
    let component: GradeComponent
    let isNew: Bool
    var name: String
    var group: String
    var weight: Double
    var aggregation: Aggregation
    var expectedCount: Int?

    init(workspace: Workspace, course: LoadedCourse, component: GradeComponent) {
        self.workspace = workspace
        self.course = course
        self.component = component
        isNew = !course.file.components.contains { $0.id == component.id }
        name = component.name
        group = component.group ?? ""
        weight = component.weight
        aggregation = component.aggregation
        expectedCount = component.expectedCount
    }

    var sheetTitle: String { String(localized: isNew ? .componentSheetAdd : .componentSheetEdit) }
    var confirmTitle: String { String(localized: isNew ? .commonAdd : .commonSave) }

    var invalid: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty || weight < 0 || (expectedCount ?? 1) < 1 }

    /// How many scores the rule drops or keeps; nil for rules without a count.
    var count: Int? {
        switch aggregation {
        case .dropLowest(let n), .bestOf(let n): n
        default: nil
        }
    }

    var aggregationOptions: [(Aggregation, String)] {
        let n = count ?? 1
        return [(.sum, String(localized: .aggregationSum)), (.mean, String(localized: .aggregationMean)), (.single, String(localized: .aggregationSingle)),
                (.dropLowest(n), String(localized: .componentSheetDropLowest)), (.bestOf(n), String(localized: .componentSheetBestOf))]
    }

    var dropsLowest: Bool { aggregation == .dropLowest(count ?? 1) }

    var countLabel: String { String(localized: dropsLowest ? .componentSheetDropCount : .componentSheetKeepCount) }

    var countValue: Int {
        get { count ?? 1 }
        set { aggregation = dropsLowest ? .dropLowest(newValue) : .bestOf(newValue) }
    }

    var countOptions: [(Int, String)] { (1...10).map { ($0, String(localized: .componentSheetTimes($0))) } }

    func confirm() -> Bool {
        let saved = isNew
            ? workspace.run(ComponentAdd(id: component.id, course: course.id, name: name, weight: weight, aggregation: aggregation,
                                         expectedCount: expectedCount, group: group))
            : workspace.run(ComponentSet(course: course.id, component: component.id, name: .set(name), weight: .set(weight),
                                         aggregation: .set(aggregation), expectedCount: .set(expectedCount), group: .set(group)))
        return saved != nil
    }

    /// Its scores go with it; assignments and exams that fed it stay, unlinked.
    func remove() { workspace.run(ComponentRemove(course: course.id, component: component.id)) }
}

/// Percents are typed as text and stored as fractions; an empty field means the rule is unset.
@MainActor @Observable
final class PolicyModel {
    let workspace: Workspace
    let course: LoadedCourse
    var caps: [AttendanceCap]
    var ratio: String
    var late: String
    var notes: String
    var topShare: String
    var lates: String

    init(workspace: Workspace, course: LoadedCourse) {
        self.workspace = workspace
        self.course = course
        let p = course.file.policy
        caps = p.attendanceCap.sorted { $0.absences < $1.absences }
        ratio = p.minAttendanceRatio.map { ($0 * 100).formatted(.number.precision(.fractionLength(0...1))) } ?? ""
        late = p.latePolicy ?? ""
        notes = p.notes
        topShare = p.topGradeRatio.map { ($0 * 100).formatted(.number.precision(.fractionLength(0...1))) } ?? ""
        lates = p.latesPerAbsence.map(String.init) ?? ""
    }

    var isRelative: Bool { course.file.course.gradingMode == .relative }

    var defaultTopShare: String { "\(Int(GradePolicy.defaultTopGradeRatio * 100))" }

    var grades: [LetterGrade] { workspace.catalog.letterGrades.filter { $0.points != nil }.sorted { $0.points! > $1.points! } }

    var invalid: Bool {
        let badShare = !topShare.isEmpty && !(Double(topShare).map { $0 > 0 && $0 < 100 } ?? false)
        let badLates = !lates.isEmpty && !(Int(lates).map { $0 > 0 } ?? false)
        let badRatio = !ratio.isEmpty && !(Double(ratio).map { $0 > 0 && $0 <= 100 } ?? false)
        return badRatio || badShare || badLates
    }

    /// A new cap starts one absence past the highest at the lowest grade, the usual next step.
    func addCap() {
        guard let lowest = grades.last else { return }
        caps.append(AttendanceCap(absences: (caps.map(\.absences).max() ?? 5) + 1, maxGrade: lowest.id))
    }

    /// Guards the index: a row's field can still write for a moment after its cap was removed.
    func cap(_ i: Int) -> AttendanceCap { caps.indices.contains(i) ? caps[i] : AttendanceCap(absences: 0, maxGrade: UUID()) }

    func setCap(_ i: Int, _ cap: AttendanceCap) { if caps.indices.contains(i) { caps[i] = cap } }

    func confirm() -> Bool {
        var policy = course.file.policy
        policy.attendanceCap = caps
        policy.minAttendanceRatio = Double(ratio).map { $0 / 100 }
        policy.latePolicy = late.isEmpty ? nil : late
        policy.notes = notes
        policy.topGradeRatio = Double(topShare).map { $0 / 100 }
        policy.latesPerAbsence = Int(lates)
        return workspace.run(PolicySet(course: course.id, policy: policy)) != nil
    }
}
