import FolioDomain
import FolioStorage
import Foundation

#if os(macOS)
extension ActionContext {
    func backupStore() throws -> BackupStore {
        BackupStore(gist: gist, folder: URL(filePath: (try settings().backup.folder as NSString).expandingTildeInPath, directoryHint: .isDirectory))
    }
}

/// Today's archive in the backup folder from settings.json (docs/SPEC.md "백업"). Nothing inside the GIST folder
/// changes, so the archive's path goes to `notes` rather than `changes`.
@Action("backup create", "오늘 백업을 만든다", effect: .creates, done: "백업을 만들었습니다", phrases: ["백업하기"], cli: .manual)
public struct BackupCreate {
    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.backupStore()
        let today = LocalDate(ctx.now, in: ctx.calendar)
        let target = store.folder.appending(path: "Folio-\(today).zip").path
        guard !ctx.dryRun else { return ctx.note("만들 백업: \(target)") }
        do {
            let url = try store.backUp(today: today, dailyDays: try ctx.settings().backup.dailyDays, calendar: ctx.calendar)
            ctx.note("백업: \(url.path(percentEncoded: false))")
        } catch BackupStore.Failure.insideGIST(let folder) {
            throw ActionError.rule("백업 폴더가 GIST 폴더 안에 있습니다: \(folder)")
        }
    }
}

/// Extracts one course's Notes, Ink and .folio from the archive of `day` into a new folder beside the backup folder.
/// Never writes into the GIST folder; the extracted folder's path is the action's only note.
@Action("backup restore", "한 과목을 백업에서 새 폴더로 꺼낸다", effect: .creates, done: "과목 '{course}'을(를) {day} 백업에서 꺼냈습니다", phrases: ["백업에서 복구", "되살리기"], cli: .manual)
public struct BackupRestore {
    @Arg var course: Course.ID
    @Arg var day: LocalDate

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.backupStore()
        let courseStore = try ctx.store(course)
        guard let archive = store.archives().first(where: { $0.day == day }) else { throw ActionError.notFound("\(day) 백업을 찾지 못했습니다") }
        let stamp = ctx.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let target = store.folder.deletingLastPathComponent().appending(path: "restored")
            .appending(path: "\(courseStore.url.lastPathComponent) (\(day)) \(stamp)")
        guard !ctx.dryRun else { return ctx.note(target.path(percentEncoded: false)) }
        do {
            try store.restore(course: courseStore, from: archive, to: target)
        } catch BackupStore.Failure.courseNotInBackup(let path) {
            throw ActionError.notFound("이 백업에 없는 과목입니다: \(path)")
        } catch BackupStore.Failure.targetExists(let path) {
            throw ActionError.conflict("이미 있는 폴더입니다: \(path)")
        }
        ctx.note(target.path(percentEncoded: false))
    }
}
#endif
