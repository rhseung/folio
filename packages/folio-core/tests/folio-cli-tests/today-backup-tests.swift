@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

struct TodayBackupTests {
    let h = Harness()

    func json(_ r: Harness.Result) throws -> [String: Any] {
        #expect(r.code == 0, "\(r.err)")
        return try #require(try JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: Any])
    }

    @Test func todayGathersClassesDeadlinesExamsAndReviewNotes() throws {
        let gist = try Harness.fixtureCopy()
        for line in [
            ["session", "add", "EC4207", "--date", "2026-10-26 10:30"],
            ["session", "add", "EC4207", "--date", "2026-10-28 13:00"],
            ["assignment", "add", "EC4207", "HW3", "--due", "2026-10-30 23:59"],
            ["exam", "add", "EC4207", "기말고사", "--kind", "final", "--start", "2026-11-02 10:00"],
        ] { #expect(h.cli(line, gist: gist).code == 0, "\(line)") }
        let out = try json(h.cli(["today", "--json"], gist: gist))
        let titles = { (key: String) in (out[key] as? [[String: Any]] ?? []).compactMap { $0["title"] as? String } }
        #expect(titles("classes").count == 1)
        #expect(titles("deadlines") == ["HW3"])
        #expect(titles("exams") == ["기말고사"])
        #expect((out["exams"] as? [[String: Any]])?.first?["detail"] as? String == "D-5")
        #expect(titles("reviewNotes").count == 1)
        #expect(h.cli(["today"], gist: gist).out.contains("HW3"))
    }

    @Test func transcriptListsCoursesPerSemester() throws {
        let gist = try Harness.fixtureCopy()
        let r = h.cli(["transcript", "list", "--json"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        let rows = try #require(try JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [[String: Any]])
        #expect(rows.contains { $0["code"] as? String == "MA2001" && $0["semester"] as? String == "2026-1" })
        #expect(try json(h.cli(["transcript", "show", "2026-1", "--json"], gist: gist))["courses"] as? [Any] != nil)
    }

    @Test func mistypedCommandsGetASuggestion() {
        let gist = URL(filePath: "/nonexistent")
        let r = h.cli(["exam", "ad", "EC4207"], gist: gist)
        #expect(r.code == 2)
        #expect(r.err.contains("folio exam add"))
        #expect(h.cli(["sesion", "list"], gist: gist).err.contains("folio session"))
    }

    /// Both copies back up into one shared folder, so their settings.json match; each run's output is checked and cleared.
    func backupCopies() throws -> (URL, URL, URL) {
        let (a, b) = (try Harness.fixtureCopy(), try Harness.fixtureCopy())
        // Restores land beside the backup folder, so it gets a parent of its own.
        let folder = FileManager.default.temporaryDirectory.appending(path: "folio-backups-\(UUID().uuidString)/auto")
        for gist in [a, b] {
            var settings = try GISTStore(url: gist).loadSettings().model
            settings.backup.folder = folder.path
            try h.direct(SettingsSet(settings: settings), gist: gist)
        }
        return (a, b, folder)
    }

    func expectSameFiles(_ a: URL, _ b: URL) throws {
        let (fa, fb) = (try Harness.files(a), try Harness.files(b))
        #expect(fa.keys.sorted() == fb.keys.sorted())
        for (path, data) in fa where Harness.canonical(fb[path]) != Harness.canonical(data) { Issue.record("\(path) differs") }
    }

    @Test func backupCreateMatchesTheAction() throws {
        let (a, b, folder) = try backupCopies()
        let archive = folder.appending(path: "Folio-2026-10-28")
        #expect(h.cli(["backup", "create", "--dry-run"], gist: a).code == 0)
        #expect(!FileManager.default.fileExists(atPath: archive.path))
        #expect(h.cli(["backup", "create"], gist: a).code == 0)
        #expect(FileManager.default.fileExists(atPath: archive.path))
        try FileManager.default.removeItem(at: archive)
        try h.direct(BackupCreate(), gist: b)
        #expect(FileManager.default.fileExists(atPath: archive.path))
        try expectSameFiles(a, b)
        #expect(h.cli(["backup", "list", "--json"], gist: a).out.contains("2026-10-28"))
    }

    @Test func backupRestoreMatchesTheAction() throws {
        let (a, b, folder) = try backupCopies()
        try h.direct(BackupCreate(), gist: a)
        let restored = folder.deletingLastPathComponent().appending(path: "restored")
        let r = h.cli(["backup", "restore", "EC4207", "2026-10-28"], gist: a)
        #expect(r.code == 0, "\(r.err)")
        let made = try FileManager.default.contentsOfDirectory(atPath: restored.path)
        #expect(made.count == 1 && made[0].hasPrefix("EC4207 그래프 이론 (2026-10-28)"))
        #expect(FileManager.default.fileExists(atPath: restored.appending(path: made[0]).appending(path: ".folio/course.json").path))
        try FileManager.default.removeItem(at: restored)
        try h.direct(BackupRestore(course: Harness.graphTheory, day: LocalDate("2026-10-28")!), gist: b)
        #expect(try FileManager.default.contentsOfDirectory(atPath: restored.path) == made)
        try expectSameFiles(a, b)
        #expect(h.cli(["backup", "restore", "EC4207", "2026-01-01"], gist: a).code == 3)
    }
}
