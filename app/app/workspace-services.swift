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

    struct StudyBar: Identifiable, Sendable {
        var id: String { "\(day)-\(courseId)" }
        var day: LocalDate
        var courseId: UUID
        var seconds: TimeInterval
    }

    func recentStudyTime(days: Int, now: Date) async -> [StudyBar] {
        let stores = currentCourses.map { ($0.id, $0.store) }
        let settings = settings, calendar = calendar
        let first = settings.studyDay(of: now, calendar: calendar).adding(days: -(days - 1))
        return await Task.detached {
            stores.flatMap { id, store in
                let sessions = ((try? store.log.readAll()) ?? []).events(StudySessionEvent.self).map(\.event)
                return StudyTime.perDay(sessions, settings: settings, calendar: calendar)
                    .filter { $0.key >= first }
                    .map { StudyBar(day: $0.key, courseId: id, seconds: $0.value) }
            }
        }.value
    }

    // MARK: Catalog

    /// Saves catalog.json; rows that changed are stamped as edited from this device. Unknown keys in the file are kept.
    func saveCatalog(_ new: Catalog) {
        guard catalogLoaded else {
            error = "catalog.json을 읽지 못해 저장하지 않았습니다. 파일을 확인한 뒤 다시 읽기를 누르세요."
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

    /// Off the main actor: zipping every course's notes takes seconds. Nothing in the GIST folder changes, so no reload.
    @discardableResult
    func backUpNow() async -> Bool {
        guard let gist else { return false }
        let device = device, calendar = calendar
        do {
            try await Task.detached { try BackupCreate().run(ActionContext(gist: gist, device: device, calendar: calendar)) }.value
            return true
        } catch {
            self.error = "백업하지 못했습니다: \(error)"
            return false
        }
    }

    func backUpIfDue() async {
        guard settings.backup.enabled, !runsOnFixture, let store = backupStore,
              store.archives().first?.day != LocalDate(.now, in: calendar) else { return }
        await backUpNow()
    }

    /// Extracts the course's Notes, Ink and .folio from a backup into a new folder beside the backup folder,
    /// outside GIST, and returns it. Nothing in the GIST folder is touched.
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
            self.error = "복원하지 못했습니다: \(error)"
            return nil
        }
    }
    #endif
}
