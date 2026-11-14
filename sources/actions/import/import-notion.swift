import FolioDomain
import FolioStorage
import Foundation

@Action(
    "import notion", "노션 학기, 강의, 성적을 transcript.json, catalog.json, course.json으로",
    discussion: """
        export.json은 Notion MCP로 읽은 내용을 NotionExport 형식으로 담은 파일이다. transcript.json이나 catalog.json이
        이미 있으면 실행하지 않고(종료 코드 4), course.json이 있는 과목 폴더는 건너뛴다. 학기별 GPA를 노션 값과 비교한다.
        """,
    effect: .creates, done: "노션을 가져왔습니다", examples: ["folio import notion ~/Downloads/export.json --dry-run"], phrases: ["노션 가져오기"])
public struct ImportNotion {
    /// NotionExport JSON
    @Arg @FromFile("export.json") var export: NotionExport

    public func run(_ ctx: ActionContext) throws {
        let gist = ctx.gist
        for existing in [gist.transcriptURL, gist.catalogURL] where FileManager.default.fileExists(atPath: existing.path) {
            throw ActionError.rule(String(localized: .errorImportExists(ctx.relative(existing))))
        }
        let r = NotionImporter.convert(export, gist: try gist.readTree(), device: ctx.device, now: ctx.now)
        let courses = r.courseFiles.values.map(\.course)
        func gpa(_ name: String, _ s: GPACalculator.Summary) {
            ctx.note(
                String(
                    localized: .noteImportNotionGpa(
                        name, s.totalCredits.formatted(), s.effectiveCredits.formatted(), GPACalculator.label(s.gpa))))
        }
        for semester in r.transcript.semesters.sorted(by: { $0.order < $1.order }) {
            gpa(
                semester.folder?.name ?? String(localized: .valueCreditedSemester),
                GPACalculator.semester(semester, courses: courses, catalog: r.catalog))
        }
        gpa(
            String(localized: .valueCumulative),
            GPACalculator.cumulative(semesters: r.transcript.semesters, courses: courses, catalog: r.catalog))
        gpa(String(localized: .valueMajor), GPACalculator.major(courses: courses, catalog: r.catalog))

        ctx.record(Change(.added, ctx.relative(gist.catalogURL)))
        ctx.record(Change(.added, ctx.relative(gist.transcriptURL)))
        for (folder, file) in r.courseFiles.sorted(by: { $0.key < $1.key }) {
            let store = CourseStore(url: gist.url.appending(path: folder))
            if FileManager.default.fileExists(atPath: store.courseFileURL.path) {
                ctx.note(String(localized: .noteImportNotionCourseExists(folder)))
            } else {
                ctx.record(Change(.added, ctx.relative(store.courseFileURL)))
                ctx.note(
                    String(
                        localized: .noteImportNotionCourse(
                            folder, file.components.count, file.scores.count, file.exams.count, file.policy.attendanceCap.count)))
            }
        }
        for w in r.warnings { ctx.note(String(localized: .noteImportCheck(w))) }
        guard !ctx.dryRun else { return }
        _ = try gist.write(r)
        ctx.invalidate()
    }
}
