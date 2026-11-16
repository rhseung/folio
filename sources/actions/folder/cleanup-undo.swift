import FolioDomain
import FolioStorage
import Foundation

@Action(
    "cleanup undo", "cleanup apply, material mv, note retitle, note mv, recording retitle로 옮긴 묶음을 되돌리기", effect: .moves,
    confirm: "묶음 {batch}의 이동을 되돌립니다.", done: "묶음 {batch}의 이동을 되돌렸습니다",
    examples: ["folio cleanup undo 6A1F0C2E-3B4D-4E5F-8A9B-0C1D2E3F4A5B --dry-run"], phrases: ["정리 되돌리기", "이동 취소"])
public struct CleanupUndo {
    /// 묶음 ID
    @Arg var batch: MoveBatch.ID
    @Hidden var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        let records = try MoveJournal.records(in: ctx.gist.url).filter { $0.batch == batch && $0.undoOf == nil }
        guard !records.isEmpty else { throw ActionError.notFound(String(localized: .errorNotFoundMoveBatch("\(batch)"))) }
        for r in records.reversed() { ctx.record(Change(.moved, r.to ?? "", to: r.from)) }
        let moves = records.reversed().compactMap { r in
            r.op == .move ? r.to.flatMap { to in r.from.map { PlannedMove(from: to, to: $0) } } : nil
        }
        let undone = try NoteTitles.follow(
            moves, ctx, move: { try MoveJournal.undo(batch: batch, in: ctx.gist.url, device: ctx.device, now: ctx.now) })
        try RecordingFiles.follow(moves, ctx)
        guard let undone else { return }
        ctx.made(undone)
        ctx.invalidate()
        if let course { try MaterialTrack(course: course).run(ctx) }
    }
}
