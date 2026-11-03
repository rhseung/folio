import FolioDomain
import FolioStorage
import Foundation

// Every course has a folder. `transcript add` records a course taken before Folio (a past or credited term) with its
// grade; `transcript move` gives the courses schema v1 kept in transcript.json their folders.

@Action("transcript add", "지난 학기나 인정학기 과목의 성적 기록 추가. 과목 폴더와 course.json을 만든다", effect: .creates, done: "과목 '{title}'의 기록을 추가했습니다",
        examples: [#"folio transcript add "영재고 AP" "일반물리학 및 연습 II" --code GS --number 1102 --mode pass_fail --dry-run  인정학기 과목"#],
        phrases: ["인정학기 과목", "성적 기록 추가", "지난 학기 과목"])
public struct TranscriptAdd {
    @New var id: Course.ID
    /// 학기
    @Arg var semester: Semester.ID
    /// 과목 이름
    @Arg var title: String
    /// 강의 코드. 과목 폴더 이름이 된다
    var code: CourseCode.ID
    /// 과목 번호. 예: 4207
    var number: String
    /// 학점
    var credits: Double = 3
    /// 평가 방식
    var mode: GradingMode = .passFail
    /// 받은 성적
    var grade: LetterGrade.ID?

    public func run(_ ctx: ActionContext) throws {
        var course = Course(id: id, device: ctx.device, at: ctx.now, semesterId: semester, title: title, codes: [code], number: number,
                            credits: credits, gradingMode: mode)
        course.finalGrade = grade
        try CourseAdd.create(course, ctx)
        ctx.made(id)
    }
}

/// Each course keeps its id, so whatever points at it (a retake, a plan) still does. The folders are journaled with the
/// courses in them, so `cleanup undo` puts the courses back in transcript.json.
@Action("transcript move", "폴더 없는 과목을 과목 폴더로 옮기기. 과목마다 같은 ID로 폴더와 course.json을 만들고 transcript.json에서 뺀다", effect: .moves,
        confirm: "폴더 없는 과목을 모두 과목 폴더로 옮깁니다.", done: "폴더 없는 과목을 과목 폴더로 옮겼습니다",
        examples: ["folio transcript move --dry-run"], phrases: ["폴더 없는 과목 옮기기", "성적 기록 옮기기"])
public struct TranscriptMove {
    /// Where each unfiled course goes, in transcript order. Refuses the whole move when one can't go, so it never
    /// stops halfway on a rule.
    public static func plan(_ ctx: ActionContext) throws -> [(course: Course, folder: String)] {
        let transcript = try ctx.transcript(), catalog = try ctx.catalog()
        var taken = Set<String>()
        return try transcript.unfiledCourses.filter { !ctx.hasFolder($0.id) }.map { course in
            guard let semester = transcript.semesters.first(where: { $0.id == course.semesterId }) else {
                throw ActionError.notFound(String(localized: .errorTranscriptMoveNoSemester(course.title)))
            }
            guard let parent = semester.coursesFolder else {
                throw ActionError.rule(String(localized: .errorCreditedNeedsSource(semester.name)))
            }
            let name = try CourseRename.folderName(title: course.title, codes: course.codes, number: course.number, catalog: catalog)
            let folder = "\(parent)/\(name)"
            guard taken.insert(folder).inserted, !FileManager.default.fileExists(atPath: ctx.gist.url.appending(path: folder).path) else {
                throw ActionError.rule(String(localized: .errorFolderExists(folder)))
            }
            return (course, folder)
        }
    }

    public func run(_ ctx: ActionContext) throws {
        guard !(try ctx.transcript().unfiledCourses.isEmpty) else { throw ActionError.notFound(String(localized: .errorTranscriptMoveNothing)) }
        let moves = try Self.plan(ctx)
        for (_, folder) in moves { ctx.record(Change(.added, folder + "/")) }
        try ctx.io(Change(.added, StandardLayout.metadataFolder + "/" + StandardLayout.movesFile)) {
            try MoveJournal.file(moves, in: ctx.gist.url, device: ctx.device, now: ctx.now)
        }
        ctx.invalidate()
        // A course that already has its folder (a move that stopped after writing it) only leaves the transcript.
        try ctx.editTranscript { $0.unfiledCourses = [] }
    }
}
