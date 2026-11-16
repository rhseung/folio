import FolioDomain
import FolioStorage
import Foundation

@Action(
    "requirement set", "졸업 요건과 학생 정보 바꾸기. 준 것만 바꾼다", discussion: "과정은 major, doubleMajor, minor, intensive.",
    done: "졸업 요건을 바꿨습니다",
    examples: [
        "folio requirement set --admission-year 2023", "folio requirement set --total-credits 130 --min-gpa 2.0",
        "folio requirement set --program major:EC --program minor:GS --dry-run",
    ],
    phrases: ["복수전공 추가", "부전공", "전공 추가", "입학 연도", "전공 선언", "복수전공"])
public struct GraduationSet {
    /// 졸업 학점
    var totalCredits: Patch<Double>
    /// 최저 평점
    var minGPA: Patch<Double>
    /// 입학 연도(학번)
    var admissionYear: Patch<Int?>
    /// 교수에게 메일을 보낼 계정
    var email: Patch<String>
    /// 선언한 과정과 그 학과의 강의 코드. 주면 목록 전체를 바꾼다
    @CLIName("program") @Parsed("program", "과정:강의 코드 앞부분. major:EC") var programs: Patch<[StudentProgram]>

    public func run(_ ctx: ActionContext) throws {
        try ctx.editTranscript { t in
            totalCredits.apply(&t.graduation.totalCredits)
            minGPA.apply(&t.graduation.minGPA)
            admissionYear.apply(&t.graduation.admissionYear)
            email.apply(&t.graduation.email)
            programs.apply(&t.graduation.programs)
        }
    }
}
