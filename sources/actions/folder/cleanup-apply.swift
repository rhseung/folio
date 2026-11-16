import FolioDomain
import FolioStorage
import Foundation

@Action(
    "cleanup apply", "검토한 계획대로 옮기기. 먼저 GIST 폴더 전체를 백업한다", effect: .moves, confirm: "파일과 폴더 {moves}을(를) 옮깁니다.", done: "파일 {moves}을(를) 옮겼습니다",
    phrases: ["정리 실행"],
    cli: .manual(reason: "계획 파일을 읽어 검토 표시된 이동을 거르고, 확인을 받은 뒤 GIST 폴더를 --backup에 백업하고 나서 실행한다"), undoable: true)
public struct CleanupApply {
    var moves: [PlannedMove]
    var removals: [String] = []
    var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        for m in moves { ctx.record(Change(.moved, m.from, to: m.to)) }
        for r in removals { ctx.record(Change(.removed, r + "/")) }
        guard !ctx.dryRun else { return }
        ctx.made(try MoveJournal.apply(moves, removing: removals, in: ctx.gist.url, device: ctx.device, now: ctx.now))
        ctx.invalidate()
        if let course { try MaterialTrack(course: course).run(ctx) }
        try annotate(ctx)
    }

    // 추적을 먼저 돌려야 파일의 자료가 새 경로를 갖고, 전에 추적하던 파일이면 id를 지킨다. 이동을 되돌려도 이 값은
    // 자료에 남는다.
    func annotate(_ ctx: ActionContext) throws {
        let annotated = moves.filter { $0.exam != nil || $0.kind != nil }
        guard !annotated.isEmpty else { return }
        for store in try ctx.gist.courseStores() {
            let base = ctx.relative(store.url) + "/"
            let mine = annotated.filter { $0.to.hasPrefix(base) }
            guard !mine.isEmpty, let id = try? store.load().model.course.id else { continue }
            if id != course { try MaterialTrack(course: id).run(ctx) }
            try ctx.edit(id) { f in
                for move in mine {
                    guard let m = f.materials.firstIndex(where: { $0.path == String(move.to.dropFirst(base.count)) }) else { continue }
                    if let kind = move.kind { f.materials[m].kind = kind }
                    guard let folder = move.exam else { continue }
                    if let exam = f.exams.first(where: { $0.folder == folder }) {
                        f.setMaterial(f.materials[m].id, exam: exam.id, linked: true)
                    } else {
                        ctx.note(String(localized: .noteCleanupUnlinked(move.to, folder)))
                    }
                }
            }
        }
    }
}
