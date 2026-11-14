import FolioDomain
import FolioStorage
import Foundation

@Action(
    "course rename", "과목 이름, 코드, 번호 바꾸기. 폴더 이름도 바뀌므로 확인을 받는다",
    discussion: "폴더 이동은 .folio/moves.jsonl에 남아 `folio cleanup undo`로 되돌릴 수 있다.",
    effect: .moves, confirm: "과목 '{course}'의 폴더 이름을 바꿉니다.", done: "과목 '{course}'의 이름을 바꿨습니다",
    examples: [#"folio course rename EC4207 --title "그래프 이론과 응용" --dry-run"#, "folio course rename EC4207 --number 4207-02"],
    phrases: ["과목 이름 변경", "과목 코드 변경"])
public struct CourseRename {
    /// 과목
    @Arg var course: Course.ID
    /// 과목 이름
    var title: Patch<String>
    /// 강의 코드 앞부분. 여러 개면 첫째가 주 코드
    @CLIName("code") var codes: Patch<[CourseCode.ID]>
    /// 일련번호
    var number: Patch<String>

    public static func folderName(title: String, codes: [UUID], number: String, catalog: Catalog) throws -> String {
        guard let prefix = codes.first.flatMap({ id in catalog.codes.first { $0.id == id } })?.prefix,
            let name = StandardLayout.courseFolderName(prefix: prefix, number: number, title: title)
        else {
            throw ActionError.rule(String(localized: .errorCourseFolderName))
        }
        return name
    }

    public func run(_ ctx: ActionContext) throws {
        let now = try ctx.file(course).course
        let (title, codes, number) = (title.value ?? now.title, codes.value ?? now.codes, number.value ?? now.number)
        let name = try Self.folderName(title: title, codes: codes, number: number, catalog: ctx.catalog())
        let from = ctx.relative(try ctx.store(course).url)
        let to = (from as NSString).deletingLastPathComponent + "/" + name

        if from != to {
            try ctx.io(Change(.moved, from, to: to)) {
                try MoveJournal.apply([PlannedMove(from: from, to: to)], in: ctx.gist.url, device: ctx.device, now: ctx.now)
                ctx.invalidate()
            }
        }
        try ctx.edit(course) {
            $0.course.title = title
            $0.course.codes = codes
            $0.course.number = number
        }
    }
}
