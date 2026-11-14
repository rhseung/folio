import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "note mv", "노트 이름 바꾸기나 Notes 안의 다른 폴더로 옮기기. 노트의 첫 제목과 다른 노트의 링크도 따라 바뀐다",
    discussion:
        #"새 이름은 Notes 폴더 기준이고 확장자는 노트 그대로다. 과목의 다른 노트가 같은 이름이면 뒤에 " 2"를 붙인다. course.json의 노트 경로, 노트의 첫 제목(아직 예전 이름일 때), 다른 노트의 [[제목]] 링크와 [[note:<ID>|제목]]의 이름(아직 예전 이름일 때)이 함께 바뀌고, 다른 폴더로 옮기면 노트 안의 상대 경로(그림)도 새 자리에 맞춘다. 이동은 moves.jsonl에 남고 folio cleanup undo로 함께 되돌린다. .tex 노트는 Folio가 빌드한 PDF(Study/<제목>.pdf)도 같은 묶음으로 새 이름을 따라가고, 새 이름의 PDF가 이미 있으면 덮어쓰지 않고 그대로 둔다. Folio가 만들지 않은 같은 이름의 PDF는 옮기지 않는다."#,
    effect: .moves, confirm: "노트 {note}을(를) Notes/{to}(으)로 옮깁니다.", done: "노트 {note}을(를) Notes/{to}(으)로 옮겼습니다",
    examples: [#"folio note mv "EC4207/시험 메모" "중간 대비" --dry-run"#, "folio note mv EC4207/09-08 정리/09-08"],
    phrases: ["노트 이름 바꾸기", "노트 이름 변경", "노트 옮기기", "노트 폴더로"], undoable: true)
public struct NoteMove {
    @Arg var course: Course.ID
    /// 노트
    @Arg var note: Note.Path
    /// 새 이름. Notes 폴더 기준이고 하위 폴더를 앞에 쓴다. 예: 정리/증명
    @Arg var to: String

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let source = try FolioActions.note(ctx, course: course, path: note)
        let name = ((to as NSString).lastPathComponent as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw ActionError.rule(String(localized: .errorNoteTitleEmpty)) }
        guard let target = store.movedNoteURL(source, to: to, in: try ctx.file(course)) else {
            throw ActionError.rule(String(localized: .errorNoteMovePlace(to)))
        }
        guard target.standardizedFileURL != source.url.standardizedFileURL else { return }

        let move = PlannedMove(from: ctx.relative(source.url), to: ctx.relative(target))
        ctx.record(Change(.moved, move.from, to: move.to))

        // 다음 빌드가 찾고 한 번의 되돌리기로 둘 다 돌아오도록, 이 노트의 빌드가 쓴 PDF도 같은 묶음에서 새 제목을 받는다.
        // 새 이름에 다른 파일이 있으면 그 파일을 남기고 PDF는 제 이름을 지킨다. 아무것도 덮어쓰지 않는다.
        let file = try ctx.file(course)
        let built = store.builtPDFMove(of: source, to: target, in: file).flatMap { $0.blocked ? nil : $0 }
        let pdf = try built.map { PlannedMove(from: try ctx.relative(course, $0.from), to: try ctx.relative(course, $0.to)) }
        if let pdf { ctx.record(Change(.moved, pdf.from, to: pdf.to)) }
        let moves = [move] + (pdf.map { [$0] } ?? [])
        guard
            let batch = try NoteTitles.follow(
                moves, ctx, move: { try MoveJournal.apply(moves, in: ctx.gist.url, device: ctx.device, now: ctx.now) })
        else { return }
        ctx.made(batch)

        if let built, let material = file.materials.first(where: { $0.path == built.from }) {
            try ctx.edit(course) { f in
                let url = store.fileURL(built.to)
                f.relinkMaterial(
                    material.id, to: built.to, hash: material.hash, size: material.size, bookmark: try? url.bookmarkData(),
                    device: ctx.device, now: ctx.now)
            }
        }
    }
}
