@testable import FolioCLI
import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

/// docs/SPEC.md "도움말": every example in the help runs on a `Fixture.standard` copy, writes as `--dry-run`.
struct HelpExampleTests {
    let h = Harness()

    /// What the examples talk about, made first on the copy through the commands themselves.
    static let world: [[String]] = [
        ["session", "add", "EC4207", "--date", "2026-09-08 10:30"],
        ["session", "add", "EC4207", "--date", "2026-10-06 10:30"],
        ["session", "add", "EC4207", "--date", "2026-10-26 10:30"],
        ["session", "add", "EC4207", "--date", "2026-10-28 10:30"],
        ["session", "add", "EC4207", "--date", "2026-10-30 10:30"],
        ["unit", "add", "EC4207", "그래프"],
        ["unit", "add", "EC4207", "트리"],
        ["unit", "add", "EC4207", "스패닝 트리", "--parent", "트리"],
        ["unit", "add", "EC4207", "매칭"],
        ["unit", "add", "EC4207", "이분 그래프"],
        ["component", "add", "EC4207", "과제", "--weight", "30"],
        ["component", "add", "EC4207", "퀴즈", "--weight", "20"],
        ["component", "add", "EC4207", "중간고사", "--weight", "50"],
        ["exam", "add", "EC4207", "중간고사", "--kind", "midterm", "--start", "2026-10-22 10:00"],
        ["exam", "add", "EC4207", "Quiz1", "--kind", "quiz", "--start", "2026-09-30 10:00"],
        ["assignment", "add", "EC4207", "HW3", "--due", "2026-11-04 23:59"],
        ["score", "add", "EC4207", "--component", "과제", "--title", "HW1", "--score", "9", "--max", "10"],
        ["problem-set", "add", "EC4207", "Exercise 1", "--problems", "1", "2", "3a"],
        ["material", "track", "EC4207"],
        ["note", "add", "EC4207", "매칭 정리", "--kind", "topic"],
        ["note", "add", "EC4207", "시험 메모"],
        ["exam", "plan", "add", "EC4207/중간고사", "--day", "2026-10-18", "트리 단원 복습"],
        ["unit", "add", "EC4321", "기구학"],
    ]

    /// The catalog and course codes the course examples need; the fixture has none.
    func prepare(_ gist: URL) throws {
        let ec = CourseCode(device: h.device, at: h.now, prefix: "EC"), gs = CourseCode(device: h.device, at: h.now, prefix: "GS")
        let grades = [("A+", 4.5), ("A0", 4.0), ("B0", 3.0), ("F", 0)].map { LetterGrade(device: h.device, at: h.now, symbol: $0.0, points: $0.1, countsInGpa: true, countsInCredits: true) }
        let catalog = Catalog(codes: [ec, gs], letterGrades: grades,
                              people: [Person(device: h.device, at: h.now, name: "김교수")])
        try h.direct(CatalogSet(catalog: catalog), gist: gist)
        // A credited term with one course that has no folder, for the transcript examples.
        let credited = UUID()
        try h.direct(SemesterAdd(id: credited, year: 2024, term: .credited, creditedHours: 9), gist: gist)
        try h.direct(TranscriptAdd(semester: credited, title: "군 복무 인정", credits: 9), gist: gist)
        try h.direct(CourseRename(course: Harness.graphTheory, title: "그래프 이론", codes: [ec.id], number: "4207-01"), gist: gist)
        let folder = gist.appending(path: "2026-3/EC4207 그래프 이론")
        try "외부에서 쓴 노트\n".write(to: folder.appending(path: "Notes/외부.md"), atomically: true, encoding: .utf8)
        try FileManager.default.copyItem(at: folder.appending(path: "Lectures/05_Matchings.pdf"), to: folder.appending(path: "Lectures/05_Matchings v2.pdf"))
        // Backups go beside the copy, never to the default ~/Backups; one archive from yesterday for `backup restore`.
        let backups = gist.deletingLastPathComponent().appending(path: "backups")
        var settings = try GISTStore(url: gist).loadSettings().model
        settings.backup.folder = backups.path
        try h.direct(SettingsSet(settings: settings), gist: gist)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try h.direct(BackupCreate(), gist: gist)
        try FileManager.default.moveItem(at: backups.appending(path: "Folio-2026-10-28.zip"), to: backups.appending(path: "Folio-2026-10-27.zip"))
        for line in Self.world { #expect(h.cli(line, gist: gist).code == 0, "\(line): \(h.cli(line + ["--dry-run"], gist: gist).err)") }
        let matching = try #require(try h.file(GISTStore(url: gist)).units.first { $0.title == "매칭" })
        let card = QuizCard(device: h.device, at: h.now, unitId: matching.id, type: .free, category: .definition, prompt: "최대 매칭의 정의", answer: "크기가 가장 큰 매칭")
        try h.direct(QuizCardSave(course: Harness.graphTheory, cards: [card], movedFrom: nil), gist: gist)
    }

    static func examples(_ type: ParsableCommand.Type = Folio.self) -> [String] {
        let config = type.configuration
        let text = config.discussion + (ObjectIdentifier(type) == ObjectIdentifier(Folio.self) ? "\n" + Folio.footer : "")
        let own = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            // Pipes, redirects, and files read from or written to the user's disk can't run here.
            .filter { $0.hasPrefix("folio ") && !$0.contains("|") && !$0.contains(">") && !$0.contains("<") && !$0.contains("~/") && !$0.contains("--file") && !$0.contains("--out") && $0.firstMatch(of: /[0-9A-F]{8}-[0-9A-F]{4}-/) == nil }
            // The column after two or more spaces says what the example does.
            .map { $0.replacing(/\s{2,}\S.*$/, with: "") }
        return own + (config.subcommands + config.groupedSubcommands.flatMap(\.subcommands)).flatMap { examples($0) }
    }

    static func words(_ line: String) -> [String] {
        var out: [String] = [], cur = "", quote: Character?
        for c in line {
            if let q = quote { if c == q { quote = nil } else { cur.append(c) } }
            else if c == "\"" || c == "'" { quote = c }
            else if c == " " { if !cur.isEmpty { out.append(cur); cur = "" } }
            else { cur.append(c) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    @Test func examplesRun() throws {
        try run(Self.examples())
    }

    /// The agent skill's examples are what agents copy, so they run too (docs/SPEC.md "에이전트용 호출").
    @Test func skillExamplesRun() throws {
        var dir = URL(filePath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: dir.appending(path: ".claude/skills/folio/SKILL.md").path) { dir.deleteLastPathComponent() }
        let text = try String(contentsOf: dir.appending(path: ".claude/skills/folio/SKILL.md"), encoding: .utf8)
        let examples = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("folio ") }
        #expect(examples.count > 10)
        try run(examples)
    }

    func run(_ examples: [String]) throws {
        let gist = try Harness.fixtureCopy()
        try prepare(gist)
        var failed: [String] = []
        for example in examples {
            var args = Array(Self.words(example).dropFirst())
            if !args.contains("--dry-run") { args.append("--dry-run") }
            let r = h.cli(args, gist: gist)
            if r.code != 0 { failed.append("\(example) → \(r.code) \(r.err.split(separator: "\n").first ?? "")") }
        }
        for f in failed { Issue.record(Comment(rawValue: "EXAMPLE " + f)) }
    }
}
