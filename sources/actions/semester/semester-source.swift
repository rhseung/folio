import FolioDomain
import FolioStorage
import Foundation

@Action(
    "semester source", "인정학기의 출처 정하기. 폴더가 있으면 _Credited/<출처> 폴더 이름도 바뀌므로 확인을 받는다", effect: .moves,
    confirm: "인정학기 '{semester}'의 출처를 '{source}'(으)로 정합니다.", done: "인정학기 '{semester}'의 출처를 '{source}'(으)로 정했습니다",
    examples: [#"folio semester source "영재고 AP" "영재고 AP 과정" --dry-run"#], phrases: ["인정학기 출처", "출처 바꾸기"])
public struct SemesterSource {
    /// 인정학기
    @Arg var semester: Semester.ID
    /// 출처. 영재고 AP
    @Arg var source: String

    public func run(_ ctx: ActionContext) throws {
        guard let old = try ctx.transcript().semesters.first(where: { $0.id == semester }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundSemester))
        }
        let edit: (inout Transcript) throws -> Void = { t in
            guard !t.semesters.contains(where: { $0.id != semester && $0.term == .credited && $0.source == source }) else {
                throw ActionError.rule(String(localized: .errorCreditedSourceTaken(source)))
            }
            try t.update(\.semesters, semester) { s in
                s.source = source
                s.touch(by: ctx.device, at: ctx.now)
            }
        }

        try ctx.checkTranscript(edit)
        if let from = old.coursesFolder, let to = StandardLayout.creditedFolder(source: source), from != to,
            FileManager.default.fileExists(atPath: ctx.gist.url.appending(path: from).path)
        {
            try ctx.io(Change(.moved, from, to: to)) {
                try MoveJournal.apply([PlannedMove(from: from, to: to)], in: ctx.gist.url, device: ctx.device, now: ctx.now)
            }
            ctx.invalidate()
        }
        try ctx.editTranscript(edit)
    }
}
