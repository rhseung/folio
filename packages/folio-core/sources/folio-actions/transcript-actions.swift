import FolioDomain
import Foundation

// Courses without a folder (credited terms, colloquia) keep only a grade record in transcript.json (docs/SPEC.md
// "기존 데이터 이전"). Courses with a folder are changed with `course set`.

@Action("transcript add", "폴더 없는 과목의 성적 기록 추가. 인정학기 과목, 콜로퀴움 등", effect: .creates, done: "과목 '{title}'의 기록을 추가했습니다",
        examples: [#"folio transcript add "2024 credited" "군 복무 인정" --credits 9 --mode pass_fail --dry-run  인정학기 과목"#],
        phrases: ["인정학기 과목", "성적 기록 추가", "폴더 없는 과목"])
public struct TranscriptAdd {
    @New var id: Course.ID
    /// 학기
    @Arg var semester: Semester.ID
    /// 과목 이름
    @Arg var title: String
    /// 학점
    var credits: Double = 3
    /// 평가 방식
    var mode: GradingMode = .passFail
    /// 받은 성적
    var grade: LetterGrade.ID?
    /// 강의 코드
    var code: CourseCode.ID?
    /// 과목 번호. 예: 4207
    var number: String = ""

    public func run(_ ctx: ActionContext) throws {
        guard !ctx.hasFolder(id) else { throw ActionError.rule(String(localized: .errorIdTakenCourse("\(id)"))) }
        var course = Course(id: id, device: ctx.device, at: ctx.now, semesterId: semester, title: title, codes: code.map { [$0] } ?? [],
                            number: number, credits: credits, gradingMode: mode)
        course.finalGrade = grade
        try ctx.editTranscript { t in
            guard !t.courses.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenCourse("\(id)"))) }
            t.courses.append(course)
        }
        ctx.made(id)
    }
}

@Action("transcript set", "폴더 없는 과목의 성적 기록 바꾸기. 준 것만 바꾼다", done: "과목 '{course}'의 기록을 바꿨습니다",
        examples: [#"folio transcript set "군 복무 인정" --credits 6 --dry-run"#],
        phrases: ["인정 학점 바꾸기", "성적 기록 고치기"])
public struct TranscriptSet {
    /// 과목
    @Arg var course: Course.ID
    /// 과목 이름
    var title: Patch<String>
    /// 학기
    var semester: Patch<Semester.ID>
    /// 학점
    var credits: Patch<Double>
    /// 평가 방식
    var mode: Patch<GradingMode>
    /// 받은 성적
    var grade: Patch<LetterGrade.ID?>

    public func run(_ ctx: ActionContext) throws {
        guard !ctx.hasFolder(course) else { throw ActionError.rule(String(localized: .errorTranscriptHasFolderSet)) }
        try ctx.editTranscript { t in
            try t.update(\.courses, course) { c in
                title.apply(&c.title)
                if case .set(let s) = semester { c.semesterId = s }
                credits.apply(&c.credits)
                mode.apply(&c.gradingMode)
                grade.apply(&c.finalGrade)
                c.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}

@Action("transcript rm", "폴더 없는 과목의 성적 기록 지우기", effect: .removes, confirm: "과목 '{course}'의 성적 기록을 지웁니다.",
        done: "과목 '{course}'의 기록을 지웠습니다", examples: [#"folio transcript rm "군 복무 인정" --dry-run"#],
        phrases: ["성적 기록 지우기", "인정학기 과목 지우기"])
public struct TranscriptRemove {
    /// 과목
    @Arg var course: Course.ID

    public func run(_ ctx: ActionContext) throws {
        guard !ctx.hasFolder(course) else { throw ActionError.rule(String(localized: .errorTranscriptHasFolderRm)) }
        try ctx.editTranscript { try $0.remove(Course.self, course) }
    }
}
