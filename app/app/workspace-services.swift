import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    /// A development run against a fixture copy must not notify about fake deadlines or back up into the real backup folder.
    var runsOnFixture: Bool { ProcessInfo.processInfo.environment[Self.environmentKey] != nil }

    // MARK: Study time

    func logStudySession(course id: UUID, _ span: DateInterval, screen: String) {
        // Glances under a minute are noise in a per-day chart.
        guard span.duration >= 60, let course = course(id) else { return }
        perform {
            // folio:not-an-action study time is an activity log, not a data change
            try course.store.log.append(StudySessionEvent(courseId: id, start: span.start, end: span.end, screen: screen), device: device, at: span.end)
        }
    }

    // MARK: Catalog

    /// Saves catalog.json; rows that changed are stamped as edited from this device. Unknown keys in the file are kept.
    func saveCatalog(_ new: Catalog) {
        guard catalogLoaded else {
            error = String(localized: .workspaceCatalogUnreadable)
            return
        }
        run(CatalogSet(catalog: new))
    }

    func saveSettings(_ new: Settings) {
        run(SettingsSet(settings: new))
    }

    // MARK: Backup

    #if os(macOS)
    var backupStore: BackupStore? {
        gist.map { BackupStore(gist: $0, folder: URL(filePath: (settings.backup.folder as NSString).expandingTildeInPath, directoryHint: .isDirectory)) }
    }

    /// Off the main actor: a backup walks every file in GIST and takes seconds. Nothing in the GIST folder changes, so no reload.
    @discardableResult
    func backUpNow() async -> Bool {
        guard let gist else { return false }
        let device = device, calendar = calendar
        do {
            try await Task.detached { try BackupCreate().run(ActionContext(gist: gist, device: device, calendar: calendar)) }.value
            return true
        } catch {
            self.error = String(localized: .workspaceBackupFailed("\(error)"))
            return false
        }
    }

    func backUpIfDue() async {
        guard settings.backup.enabled, !runsOnFixture, let store = backupStore,
              store.archives().first?.day != LocalDate(.now, in: calendar) else { return }
        await backUpNow()
    }

    /// Copies the course out of a backup into a new folder beside the backup folder, outside GIST, and returns it. Nothing in the GIST folder is touched.
    func restore(_ courseId: UUID, from archive: BackupStore.Archive) async -> URL? {
        guard let gist else { return nil }
        let device = device, calendar = calendar, day = archive.day
        do {
            let notes = try await Task.detached {
                let ctx = ActionContext(gist: gist, device: device, calendar: calendar)
                try BackupRestore(course: courseId, day: day).run(ctx)
                return ctx.notes
            }.value
            return notes.last.map { URL(filePath: $0, directoryHint: .isDirectory) }
        } catch {
            self.error = String(localized: .workspaceRestoreFailed("\(error)"))
            return nil
        }
    }
    #endif
}
