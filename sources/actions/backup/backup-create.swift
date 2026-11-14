import FolioDomain
import FolioStorage
import Foundation

#if os(macOS)
@Action(
    "backup create", "오늘 백업을 만든다",
    discussion: """
        설정의 백업 폴더(기본 ~/Backups/Folio/auto)에 오늘 백업을 만든다. GIST 폴더와 같은 디스크면 GIST 전체를 APFS 복제로 Folio-<날짜> 폴더에 떠서 바뀐 파일만큼만 공간을 쓴다. iCloud에만 있는 파일은 내려받지 않고 건너뛴다. 다른 디스크면 GIST의 .folio와 각 과목의 Notes, Ink, .folio를 Folio-<날짜>.zip으로 묶는다.
        오늘 백업이 있으면 바꾼다. 보관 기간이 지난 백업은 지운다. GIST 폴더는 바뀌지 않는다.
        """,
    effect: .creates, done: "백업을 만들었습니다", examples: ["folio backup create --dry-run", "folio backup create"], phrases: ["백업하기"])
public struct BackupCreate {
    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.backupStore()
        let today = LocalDate(ctx.now, in: ctx.calendar)
        guard !ctx.dryRun else {
            return ctx.note(String(localized: .noteBackupPlanned(store.target(for: today).path(percentEncoded: false))))
        }
        do {
            let created = try store.backUp(today: today, dailyDays: try ctx.settings().backup.dailyDays, calendar: ctx.calendar)
            ctx.note(String(localized: .noteBackupCreated(created.url.path(percentEncoded: false))))
            if created.skipped > 0 { ctx.note(String(localized: .noteBackupSkipped(created.skipped))) }
        } catch BackupStore.Failure.insideGIST(let folder) {
            throw ActionError.rule(String(localized: .errorBackupInsideGist(folder)))
        }
    }
}
#endif
