import FolioDomain
import FolioStorage
import Foundation

/// Bookmarks stay with the transcripts, and a recording with no transcript keeps its audio (`RecordingRetention`).
@Action("recording trim", "지난 학기 녹음의 오디오를 휴지통으로 옮기고 받아쓰기는 남기기",
        discussion: "받아쓰기가 없는 녹음은 오디오를 남긴다. 휴지통에서 되살릴 수 있다.", effect: .removes,
        confirm: "{semester}의 녹음 오디오를 휴지통으로 옮깁니다. 받아쓰기는 남습니다.", done: "{semester}의 녹음 오디오를 휴지통으로 옮겼습니다",
        examples: ["folio recording trim 2026-1 --dry-run"], phrases: ["녹음 용량", "녹음 정리", "오디오 지우기", "지난 학기 녹음"])
public struct RecordingTrim {
    /// 학기. 2026-1 또는 "2026 spring"
    @Arg var semester: Semester.ID

    public func run(_ ctx: ActionContext) throws {
        let semesters = try ctx.transcript().semesters
        let s = semesters[try index(semester, in: semesters, .valueSemester)]
        guard s.isOver(on: LocalDate(ctx.now, in: ctx.calendar), among: semesters) else {
            throw ActionError.rule(String(localized: .errorRecordingSemesterNotOver))
        }

        for store in try ctx.gist.courseStores() {
            let file = try store.load().model
            guard file.course.semesterId == semester else { continue }
            let course = file.course.id
            let trimmed = RecordingRetention.trimmable(file.recordings) { store.transcript(of: $0)?.lines.isEmpty == false }
            guard !trimmed.isEmpty else { continue }
            // The entry goes first: audio left behind by a failed trash is harmless, an entry saying there is audio
            // where there is none sends the player to a missing file and keeps the notice counting it.
            let ids = Set(trimmed.map(\.id))
            try ctx.edit(course) { f in
                for i in f.recordings.indices where ids.contains(f.recordings[i].id) {
                    f.recordings[i].audioTrashedAt = ctx.now
                    f.recordings[i].touch(by: ctx.device, at: ctx.now)
                }
            }

            for r in trimmed {
                ctx.record(Change(.removed, try ctx.relative(course, r.file)))
                if !ctx.dryRun { try store.trashAudio(of: r) }
            }
        }
    }
}

/// Renames recordings still named `3주차-1.m4a` after their class's day, as new ones are named (#325). The audio and
/// its transcript move as one `moves.jsonl` batch (`made`); `cleanup undo` of it puts them back, and the entries follow
/// both ways.
@Action("recording retitle", "예전 이름(3주차-1)의 녹음 파일을 날짜 이름(11-03(화))으로 바꾸기. 받아쓰기 파일도 함께 바뀐다",
        discussion: #"회차에 연결된 녹음 중 파일 이름이 아직 `3주차-1.m4a`, `3주차-1 2.m4a`인 것만 그 수업 날짜(`11-03(화).m4a`)로 바꾼다. 같은 날 녹음이 둘이면 뒤에 " 2"를 붙인다. 직접 지은 이름과 회차 없는 녹음은 그대로 둔다. 오디오와 받아쓰기(.transcript.json)는 moves.jsonl에 한 묶음으로 남고, folio cleanup undo로 함께 되돌린다. 실제 폴더에서는 folio backup create로 백업한 뒤 --dry-run으로 먼저 본다."#,
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
                // Trimmed audio is in the Trash, and audio still being compressed isn't in the folder yet: only the
                // files that are there move, and with neither there is nothing to rename.
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

/// A recording's entry names its audio, so moving the audio or its transcript renames the entry.
enum RecordingFiles {
    /// Points each recording whose audio or transcript is in `moves` (GIST-relative, as `moves.jsonl` keeps them) at
    /// its new place, keeping the audio's extension. Courses no move reaches aren't loaded.
    static func follow(_ moves: [PlannedMove], _ ctx: ActionContext) throws {
        for store in try ctx.gist.courseStores() {
            let prefix = ctx.relative(store.url) + "/"
            let byPath = Dictionary(moves.filter { $0.from.hasPrefix(prefix) && $0.to.hasPrefix(prefix) }
                .map { (String($0.from.dropFirst(prefix.count)), String($0.to.dropFirst(prefix.count))) }, uniquingKeysWith: { a, _ in a })
            guard !byPath.isEmpty else { continue }
            let course = try store.load().model.course.id
            try ctx.edit(course) { f in
                for i in f.recordings.indices {
                    let r = f.recordings[i]
                    let file = byPath[r.file] ?? byPath[r.transcriptFile].flatMap { to in
                        to.hasSuffix(Recording.transcriptSuffix)
                            ? String(to.dropLast(Recording.transcriptSuffix.count)) + "." + (r.file as NSString).pathExtension : nil
                    }
                    guard let file, file != r.file else { continue }
                    f.recordings[i].file = file
                    f.recordings[i].touch(by: ctx.device, at: ctx.now)
                }
            }
        }
    }
}
