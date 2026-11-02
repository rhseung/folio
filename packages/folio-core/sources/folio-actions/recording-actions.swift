import FolioDomain
import FolioStorage
import Foundation

/// A finished semester's lecture audio to the Trash, where it can still be put back. Transcripts and bookmarks stay,
/// and a recording with no transcript keeps its audio (`RecordingRetention`).
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
