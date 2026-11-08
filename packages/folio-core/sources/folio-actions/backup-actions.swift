import FolioDomain
import FolioStorage
import Foundation

#if os(macOS)
extension ActionContext {
    func backupStore() throws -> BackupStore {
        BackupStore(gist: gist, folder: URL(filePath: (try settings().backup.folder as NSString).expandingTildeInPath, directoryHint: .isDirectory))
    }
}

/// Today's archive in the backup folder from settings.json. Nothing inside the GIST folder
/// changes, so the archive's path goes to `notes` rather than `changes`.
@Action("backup create", "오늘 백업을 만든다",
        discussion: """
        설정의 백업 폴더(기본 ~/Backups/Folio/auto)에 오늘 백업을 만든다. GIST 폴더와 같은 디스크면 GIST 전체를 APFS 복제로 Folio-<날짜> 폴더에 떠서 바뀐 파일만큼만 공간을 쓴다. iCloud에만 있는 파일은 내려받지 않고 건너뛴다. 다른 디스크면 GIST의 .folio와 각 과목의 Notes, Ink, .folio를 Folio-<날짜>.zip으로 묶는다.
        오늘 백업이 있으면 바꾼다. 보관 기간이 지난 백업은 지운다. GIST 폴더는 바뀌지 않는다.
        """,
        effect: .creates, done: "백업을 만들었습니다", examples: ["folio backup create --dry-run", "folio backup create"], phrases: ["백업하기"])
public struct BackupCreate {
    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.backupStore()
        let today = LocalDate(ctx.now, in: ctx.calendar)
        guard !ctx.dryRun else { return ctx.note(String(localized: .noteBackupPlanned(store.target(for: today).path(percentEncoded: false)))) }
        do {
            let created = try store.backUp(today: today, dailyDays: try ctx.settings().backup.dailyDays, calendar: ctx.calendar)
            ctx.note(String(localized: .noteBackupCreated(created.url.path(percentEncoded: false))))
            if created.skipped > 0 { ctx.note(String(localized: .noteBackupSkipped(created.skipped))) }
        } catch BackupStore.Failure.insideGIST(let folder) {
            throw ActionError.rule(String(localized: .errorBackupInsideGist(folder)))
        }
    }
}

/// Copies one course out of the backup of `day` into a new folder beside the backup folder.
/// Never writes into the GIST folder; the extracted folder's path is the action's only note.
@Action("backup restore", "한 과목을 백업에서 새 폴더로 꺼낸다",
        discussion: "과목을 백업 폴더 옆 restored 폴더에 새로 꺼낸다. 복제 백업이면 과목 폴더 전체, zip 백업이면 Notes, Ink, .folio를 꺼낸다. GIST 폴더는 건드리지 않으니 비교해서 직접 옮긴다.",
        effect: .creates, done: "과목 '{course}'을(를) {day} 백업에서 꺼냈습니다",
        examples: ["folio backup restore EC4207 2026-10-27 --dry-run", "folio backup restore EC4207 2026-10-27"], phrases: ["백업에서 복구", "되살리기"])
public struct BackupRestore {
    /// 과목
    @Arg var course: Course.ID
    /// 백업 날짜. 2026-10-27
    @Arg var day: LocalDate

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.backupStore()
        let courseStore = try ctx.store(course)
        guard let archive = store.archives().first(where: { $0.day == day }) else { throw ActionError.notFound(String(localized: .errorNotFoundBackup("\(day)"))) }
        let stamp = ctx.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let target = store.folder.deletingLastPathComponent().appending(path: "restored")
            .appending(path: "\(courseStore.url.lastPathComponent) (\(day)) \(stamp)")
        guard !ctx.dryRun else { return ctx.note(target.path(percentEncoded: false)) }
        do {
            try store.restore(course: courseStore, from: archive, to: target)
        } catch BackupStore.Failure.courseNotInBackup(let path) {
            throw ActionError.notFound(String(localized: .errorNotFoundBackupCourse(path)))
        } catch BackupStore.Failure.targetExists(let path) {
            throw ActionError.conflict(String(localized: .errorFolderExists(path)))
        }
        ctx.note(target.path(percentEncoded: false))
    }
}
#endif
