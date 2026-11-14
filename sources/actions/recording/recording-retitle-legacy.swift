import FolioDomain
import FolioStorage
import Foundation

@Action(
    "recording retitle", "예전 이름(3주차-1)의 녹음 파일을 날짜 이름(11-03(화))으로 바꾸기. 받아쓰기 파일도 함께 바뀐다",
    discussion:
        #"회차에 연결된 녹음 중 파일 이름이 아직 `3주차-1.m4a`, `3주차-1 2.m4a`인 것만 그 수업 날짜(`11-03(화).m4a`)로 바꾼다. 같은 날 녹음이 둘이면 뒤에 " 2"를 붙인다. 직접 지은 이름과 회차 없는 녹음은 그대로 둔다. 오디오와 받아쓰기(.transcript.json)는 moves.jsonl에 한 묶음으로 남고, folio cleanup undo로 함께 되돌린다. 실제 폴더에서는 folio backup create로 백업한 뒤 --dry-run으로 먼저 본다."#,
    effect: .moves, confirm: "녹음 파일의 이름을 날짜로 바꿉니다.", done: "녹음 파일의 이름을 바꿨습니다",
    examples: ["folio recording retitle --dry-run", "folio recording retitle EC4207"],
    phrases: ["녹음 이름 날짜로", "예전 녹음 이름 바꾸기", "주차 이름 녹음"], undoable: true)
public struct RecordingRetitleLegacy {
    /// 과목. 빼면 모든 과목
    @Arg var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        let courses = try course.map { [$0] } ?? ctx.gist.courseStores().map { try $0.load().model.course.id }
        var moves: [PlannedMove] = []
        let name = { (path: String) in (path as NSString).lastPathComponent }
        for course in courses {
            let store = try ctx.store(course)
            let file = try ctx.file(course)
            let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: store.recordingsURL.path)) ?? []
            var taken = Set(onDisk + file.recordings.flatMap { [name($0.file), name($0.transcriptFile)] })
            for r in file.legacyRecordingRetitles(calendar: ctx.calendar) {
                guard let recording = file.recordings.first(where: { $0.id == r.recording }) else { continue }
                let parts = [r.file, recording.transcriptFile].filter { FileManager.default.fileExists(atPath: store.fileURL($0).path) }
                guard !parts.isEmpty else { continue }
                var target = Recording.file(named: r.name, taken: taken)
                while taken.contains(name(Recording.transcriptFile(of: target))) {
                    taken.insert(name(target))
                    target = Recording.file(named: r.name, taken: taken)
                }
                taken.formUnion([name(target), name(Recording.transcriptFile(of: target))])
                for part in parts {
                    let to = part == r.file ? target : Recording.transcriptFile(of: target)
                    moves.append(PlannedMove(from: try ctx.relative(course, part), to: try ctx.relative(course, to)))
                }
            }
        }

        guard !moves.isEmpty else { return }
        for move in moves { ctx.record(Change(.moved, move.from, to: move.to)) }
        let batch = ctx.dryRun ? nil : try MoveJournal.apply(moves, in: ctx.gist.url, device: ctx.device, now: ctx.now)
        try RecordingFiles.follow(moves, ctx)
        if let batch { ctx.made(batch) }
    }
}
