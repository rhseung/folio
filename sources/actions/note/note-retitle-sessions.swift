import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "note retitle", "예전 이름(10주차-2)의 회차 노트를 날짜와 단원 이름으로 바꾸기. 노트의 첫 제목과 다른 노트의 링크도 따라 바뀐다",
    discussion:
        "회차에 연결된 러프 노트와 복습 노트 중 이름이 아직 `10주차-2`, `10주차-2 정리`인 것만 바꾼다. 직접 지은 이름은 그대로 둔다. 이동은 moves.jsonl에 한 묶음으로 남고, folio cleanup undo로 이름과 제목, 링크를 함께 되돌린다. 실제 폴더에서는 folio backup create로 백업한 뒤 --dry-run으로 먼저 본다.",
    effect: .moves, confirm: "회차 노트의 이름을 날짜와 단원으로 바꿉니다.", done: "회차 노트의 이름을 바꿨습니다",
    examples: ["folio note retitle --dry-run", "folio note retitle EC4207"],
    phrases: ["노트 이름 날짜로", "예전 노트 이름 바꾸기", "주차 이름 노트"], undoable: true)
public struct NoteRetitleSessions {
    /// 과목. 빼면 모든 과목
    @Arg var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        let courses = try course.map { [$0] } ?? ctx.gist.courseStores().map { try $0.load().model.course.id }
        var moves: [PlannedMove] = []
        for course in courses {
            let store = try ctx.store(course)
            var taken = Set<String>()
            for r in try ctx.file(course).legacySessionNoteRetitles(calendar: ctx.calendar) {
                // Finder에서 파일 이름을 바꾸거나 지운 항목은 옮길 것이 없고, 그런 항목이 있으면 기록이 묶음 전체를 거절한다.
                let source = store.fileURL(r.path)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                // `newNoteURL`은 Notes/ 바로 안의 파일 이름을 정하므로, 더 깊이 둔 노트는 이름 바꾸기를 넘어 한 폴더 위로 옮겨진다.
                let url = store.newNoteURL(title: r.title, format: NoteFormat(path: r.path) ?? .markdown, avoiding: taken)
                guard source.deletingLastPathComponent().standardizedFileURL == url.deletingLastPathComponent().standardizedFileURL else {
                    continue
                }
                taken.insert(url.deletingPathExtension().lastPathComponent)
                moves.append(PlannedMove(from: try ctx.relative(course, r.path), to: ctx.relative(url)))
            }
        }

        guard !moves.isEmpty else { return }
        for move in moves { ctx.record(Change(.moved, move.from, to: move.to)) }
        if let batch = try NoteTitles.follow(
            moves, ctx, move: { try MoveJournal.apply(moves, in: ctx.gist.url, device: ctx.device, now: ctx.now) })
        {
            ctx.made(batch)
        }
    }
}
