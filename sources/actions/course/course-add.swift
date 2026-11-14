import FolioDomain
import FolioStorage
import Foundation

@Action(
    "course add", "과목 추가. 과목 폴더와 course.json을 만든다",
    discussion: "강의 코드는 catalog.json에 있어야 한다. 폴더 이름은 `<코드><번호> <과목 이름>`이다.",
    effect: .creates, done: "과목 '{title}'을(를) 추가했습니다",
    examples: [
        #"folio course add EC 3101 "자료 구조" --credits 3"#,
        #"folio course add GS 2004-02 "전공 글쓰기" --mode pass_fail --semester 2026-3 --dry-run"#,
    ],
    phrases: ["과목 추가", "수강 신청한 과목", "새 과목"])
public struct CourseAdd {
    @New var id: Course.ID
    /// 강의 코드 앞부분. EC
    @Arg var code: CourseCode.ID
    /// 일련번호. 4207-01
    @Arg var number: String
    /// 과목 이름
    @Arg var title: String
    /// 학점
    var credits: Double = 3
    /// 평가 방식
    var mode: GradingMode = .relative
    /// 학기. 빼면 지금 학기
    var semester: Semester.ID?

    public func run(_ ctx: ActionContext) throws {
        guard let semester = try semester ?? ctx.transcript().semesters.current(on: LocalDate(ctx.now, in: ctx.calendar))?.id else {
            throw ActionError.notFound(String(localized: .errorNotFoundSemester))
        }
        try Self.create(
            Course(
                id: id, device: ctx.device, at: ctx.now, semesterId: semester, title: title, codes: [code], number: number,
                credits: credits, gradingMode: mode), ctx)
        ctx.made(id)
    }

    static func create(_ course: Course, _ ctx: ActionContext) throws {
        guard let semester = try ctx.transcript().semesters.first(where: { $0.id == course.semesterId }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundSemester))
        }
        guard let parent = semester.coursesFolder else {
            throw ActionError.rule(String(localized: .errorCreditedNeedsSource(semester.name)))
        }

        // 과목 폴더는 course.json의 id로 찾으므로, 같은 id의 둘째 폴더는 찾을 수 없게 된다.
        guard !ctx.hasFolder(course.id) else { throw ActionError.rule(String(localized: .errorIdTakenCourse("\(course.id)"))) }
        let folder = try CourseRename.folderName(title: course.title, codes: course.codes, number: course.number, catalog: ctx.catalog())
        let path = "\(parent)/\(folder)"
        guard !FileManager.default.fileExists(atPath: ctx.gist.url.appending(path: path).path) else {
            throw ActionError.rule(String(localized: .errorFolderExists(path)))
        }
        try ctx.io(Change(.added, path + "/")) { try ctx.gist.createCourse(course, folderName: folder, in: semester) }
        ctx.invalidate()
    }
}
