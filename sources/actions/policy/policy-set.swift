import FolioDomain
import FolioStorage
import Foundation

@Action(
    "component policy", "성적 규칙 바꾸기. 준 것만 바꾼다", discussion: "값을 지우려면 none을 준다. --cap과 --cutoff는 주면 기존 목록을 바꾸고, none이면 비운다.",
    done: "성적 규칙을 바꿨습니다",
    examples: [
        "folio component policy EC4207 --min-attendance-ratio 0.75 --lates-per-absence 3",
        #"folio component policy EC4207 --notes "Quiz 최저 점수 1회 제외""#,
        "folio component policy EC4207 --cap 6:B0 --cap 9:F",
        "folio component policy EC4207 --cutoff A+:95 --cutoff A0:90 --top-grade-ratio none --dry-run",
    ])
public struct PolicySet {
    /// 과목
    @Arg var course: Course.ID
    /// 최소 출석 비율. 0.75
    var minAttendanceRatio: Patch<Double?>
    /// 지각 규칙 설명
    var latePolicy: Patch<String?>
    /// 지각 몇 번이 결석 한 번인지
    var latesPerAbsence: Patch<Int?>
    /// 상대평가에서 A를 받는 비율. 0.5
    var topGradeRatio: Patch<Double?>
    /// 결석 횟수마다 받을 수 있는 최대 성적. 주면 목록 전체를 바꾼다
    @CLIName("cap") @Parsed("cap", "결석 횟수:최대 성적. 6:B0") var attendanceCap: Patch<[AttendanceCap]>
    /// 절대평가의 성적별 최저 점수. 주면 목록 전체를 바꾼다
    @CLIName("cutoff") @Parsed("cutoff", "성적:최저 점수. A+:95") var cutoffs: Patch<[GradeCutoff]>
    /// 구조로 옮기지 못한 규칙 원문
    var notes: Patch<String>

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            minAttendanceRatio.apply(&f.policy.minAttendanceRatio)
            latePolicy.apply(&f.policy.latePolicy)
            latesPerAbsence.apply(&f.policy.latesPerAbsence)
            topGradeRatio.apply(&f.policy.topGradeRatio)
            attendanceCap.apply(&f.policy.attendanceCap)
            cutoffs.apply(&f.policy.cutoffs)
            notes.apply(&f.policy.notes)
            f.policy.attendanceCap.sort { $0.absences < $1.absences }
        }
    }
}
