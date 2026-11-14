import FolioActions
import FolioDomain
import Foundation
import Observation

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

    func addCap() {
        guard let lowest = grades.last else { return }
        caps.append(AttendanceCap(absences: (caps.map(\.absences).max() ?? 5) + 1, maxGrade: lowest.id))
    }

    func cap(_ i: Int) -> AttendanceCap { caps.indices.contains(i) ? caps[i] : AttendanceCap(absences: 0, maxGrade: UUID()) }

    func setCap(_ i: Int, _ cap: AttendanceCap) { if caps.indices.contains(i) { caps[i] = cap } }

    func confirm() -> Bool {
        workspace.run(
            PolicySet(
                course: course.id, minAttendanceRatio: .set(Double(ratio).map { $0 / 100 }), latePolicy: .set(late.isEmpty ? nil : late),
                latesPerAbsence: .set(Int(lates)), topGradeRatio: .set(Double(topShare).map { $0 / 100 }), attendanceCap: .set(caps),
                notes: .set(notes))) != nil
    }
}
