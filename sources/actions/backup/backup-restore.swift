import FolioDomain
import FolioStorage
import Foundation

#if os(macOS)
@Action(
    "backup restore", "한 과목을 백업에서 새 폴더로 꺼낸다",
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
        guard let archive = store.archives().first(where: { $0.day == day }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundBackup("\(day)")))
        }
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
