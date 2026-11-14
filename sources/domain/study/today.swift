import Foundation

extension CourseFile {
    public func capOneAway(at now: Date) -> (absences: Int, cap: AttendanceCap)? {
        let absences = GradeCalculator.absences(in: heldAttendance(at: now), policy: policy)
        guard let cap = GradeCalculator.nextCap(absences: absences, policy: policy), cap.absences == absences + 1 else { return nil }
        return (absences, cap)
    }
}
