@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

struct SessionCommandTests {
    let h = Harness()
    static let id = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
    static let add = ["session", "add", "EC4207", "--date", "2026-10-28 10:30", "--id", id.uuidString]

    var date: Date { DateArg(argument: "2026-10-28 10:30")!.date }

    @Test func add() throws {
        try h.expectSame(Self.add) { _ in SessionAdd(id: Self.id, course: Harness.graphTheory, date: date) }
    }

    @Test func addCancelled() throws {
        try h.expectSame(Self.add + ["--cancelled"]) { _ in SessionAdd(id: Self.id, course: Harness.graphTheory, date: date, cancelled: true) }
    }

    @Test func set() throws {
        try h.expectSame(["session", "set", "EC4207/9주차-1", "--cancelled", "true"], setup: [Self.add]) { _ in
            SessionSet(course: Harness.graphTheory, session: Self.id, cancelled: .set(true))
        }
    }

    @Test func remove() throws {
        try h.expectSame(["session", "rm", "EC4207/9주차-1", "--yes"], setup: [Self.add]) { _ in
            SessionRemove(course: Harness.graphTheory, sessions: [Self.id])
        }
    }

    @Test func note() throws {
        let note = UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!
        try h.expectSame(["session", "note", "EC4207/9주차-1", "review", "--id", note.uuidString], setup: [Self.add]) { _ in
            SessionNote(id: note, course: Harness.graphTheory, session: Self.id, kind: .review)
        }
    }

    @Test func attendance() throws {
        try h.expectSame(["attendance", "set", "EC4207/9주차-1", "absent"], setup: [Self.add]) { _ in
            AttendanceSet(course: Harness.graphTheory, session: Self.id, state: .absent)
        }
    }

    @Test func runTakesNamesLikeTheCommands() throws {
        try h.expectSame(["run", "session", "set", "--input", #"{"course":"EC4207","session":"9주차-1","cancelled":true}"#], setup: [Self.add]) { _ in
            SessionSet(course: Harness.graphTheory, session: Self.id, cancelled: .set(true))
        }
    }

    @Test func errorsHaveTheirExitCodes() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["session", "show", "XX/1주차-1"], gist: gist).code == Exit.notFound.rawValue)
        #expect(h.cli(["session", "ad"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["run", "session", "set", "--input", #"{"course":"EC4207"}"#], gist: gist).code == Exit.usage.rawValue)
        let json = h.cli(["session", "show", "EC4207/없음", "--json"], gist: gist)
        #expect(json.err.hasPrefix(#"{"error":{"candidates":"#))
    }

    @Test func hangulCountsTwoColumns() {
        #expect("그래프 이론".columns == 11)
        #expect("EC4207".columns == 6)
        #expect("그래프 이론".truncated(to: 6) == "그래…")
    }

    @Test func cuttingStyledTextKeepsItsCodes() {
        let marked = "a \u{1B}[33mhit\u{1B}[0m and more"
        let cut = marked.truncated(to: 5)
        #expect(cut.plain == "a hi…")
        // The reset past the cut is kept, so the yellow doesn't run into the next column.
        #expect(cut == "a \u{1B}[33mhi\u{1B}[0m\u{1B}[0m…")
    }
}

struct SchemaTests {
    @Test func everyActionHasAnInputShape() throws {
        guard case .object(let root) = actionSchemas(), case .array(let actions)? = root["actions"] else { Issue.record("no actions"); return }
        #expect(actions.count == Actions.all.count)
        for case .object(let a) in actions {
            guard case .object(let input)? = a["input"], case .object(let props)? = input["properties"] else {
                Issue.record("\(a["command"] ?? .null) has no input properties")
                continue
            }
            // Backing up takes nothing: the folder and retention come from settings.json.
            #expect(!props.isEmpty || a["command"] == .string("backup create"), "\(a["command"] ?? .null)")
        }
    }

    @Test func enumCasesCarryTheirPayload() throws {
        guard case .object(let root) = actionSchemas(), case .object(let defs)? = root["$defs"],
              case .object(let target)? = defs["UnitMove.Target"], case .array(let cases)? = target["oneOf"] else {
            Issue.record("no UnitMove.Target")
            return
        }
        #expect(cases.count == 2)
        #expect("\(cases[0])".contains("integer"))
    }
}

struct SearchCommandTests {
    let h = Harness()

    @Test func searchFindsNoteBodies() throws {
        let gist = try Harness.fixtureCopy()
        let r = h.cli(["search", "non-adjacent", "--json"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        let hits = try JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [[String: Any]]
        #expect(hits?.first?["kind"] as? String == "note")
        #expect(h.cli(["search", "주차", "--course", "EC4321", "--kind", "unit", "--lines"], gist: gist).code == 0)
    }
}

struct AgentTests {
    let h = Harness()

    /// The repository copy is what agents working in the repo load; it must say what `folio skill` installs.
    @Test func repositorySkillMatchesTheBinary() throws {
        var dir = URL(filePath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: dir.appending(path: ".claude/skills/folio/SKILL.md").path) { dir.deleteLastPathComponent() }
        let file = try String(contentsOf: dir.appending(path: ".claude/skills/folio/SKILL.md"), encoding: .utf8)
        #expect(file == Skill.file, "run: folio skill > .claude/skills/folio/SKILL.md")
    }

    @Test func skillInstallWritesOnceThenSaysUnchanged() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "folio-skill-\(UUID().uuidString)")
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["skill", "--install", dir.path, "--dry-run"], gist: gist).code == 0)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "folio/SKILL.md").path))
        #expect(h.cli(["skill", "--install", dir.path], gist: gist).code == 0)
        #expect(try String(contentsOf: dir.appending(path: "folio/SKILL.md"), encoding: .utf8) == Skill.file)
        #expect(h.cli(["skill", "--install", dir.path, "--json"], gist: gist).out.contains("unchanged"))
    }

    /// The evaluation's first requests, the ones the synonym table was built from, must stay on top; the rest is
    /// measured, not asserted (FinderEvaluation).
    @Test func findsCommandFromRequest() {
        for (request, answers) in FinderEvaluation.cases.prefix(11) {
            let first = Finder.find(request).first?.command.replacing("folio ", with: "")
            #expect(first.map(answers.contains) == true, "\(request) → \(first ?? "nothing")")
        }
    }

    @Test func helpWithWordsSearches() throws {
        let gist = try Harness.fixtureCopy()
        let r = h.cli(["help", "과제", "마감", "바꾸기", "--json"], gist: gist)
        #expect(r.code == 0)
        #expect(r.out.contains("folio assignment set"))
        #expect(h.cli(["help", "zzzz"], gist: gist).code == Exit.notFound.rawValue)
        // Command names and topics still go to their own help.
        #expect(h.cli(["help", "refs"], gist: gist).out.contains("가리키기"))
    }
}

/// Serialized: one test sets SAP_SHELL for the whole process.
@Suite(.serialized) struct CompletionTests {
    let h = Harness()

    /// The shell calls back with `---completion <command> -- <argument> <word index> <cursor> <words…>`.
    @Test func itemsFollowTheCourse() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["unit", "add", "EC4207", "매칭"], gist: gist).code == 0)
        let units = h.cli(["---completion", "unit", "show", "--", "positional@0", "3", "7", "folio", "unit", "show", "EC4207/"], gist: gist)
        #expect(units.out.split(separator: "\n").contains("EC4207/매칭"), "\(units.out) \(units.err)")
        let semesters = h.cli(["---completion", "search", "--", "--semester", "3", "0", "folio", "search", "--semester", ""], gist: gist)
        #expect(semesters.out.split(separator: "\n").contains("2026-3"), "\(semesters.out) \(semesters.err)")
    }

    /// zsh gets `value:note`, so a list of course codes says which course each is.
    @Test func zshCandidatesCarryANote() throws {
        let gist = try Harness.fixtureCopy()
        setenv("SAP_SHELL", "zsh", 1)
        defer { unsetenv("SAP_SHELL") }
        let courses = h.cli(["---completion", "course", "show", "--", "positional@0", "2", "0", "folio", "course", "show", ""], gist: gist)
        #expect(courses.out.split(separator: "\n").contains("EC4207:그래프 이론 · 2026-3"), "\(courses.out) \(courses.err)")
    }
}

struct GradesLockTests {
    let h = Harness()

    @Test func lockedGradesAskOrHide() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["catalog", "set", "--file", try GradesSetupTests().catalogFile(), "--yes"], gist: gist).code == 0)
        #expect(h.cli(["course", "set", "EC4207", "--grade", "A+", "--yes"], gist: gist).code == 0)
        // Commands that exist to show grades stop with 5 instead of printing them.
        for args in [["gpa"], ["transcript", "list"], ["score", "list", "EC4207"]] {
            let r = h.cli(args, gist: gist, gradesLocked: true)
            #expect(r.code == 5, "\(args)")
            #expect(!r.out.contains("A+"))
        }
        // Others keep working and hide just the grade.
        let locked = h.cli(["course", "show", "EC4207"], gist: gist, gradesLocked: true)
        #expect(locked.code == 0 && locked.out.contains("성적  ••") && !locked.out.contains("A+"))
        #expect(h.cli(["course", "show", "EC4207"], gist: gist).out.contains("성적  A+"))
    }

    @Test func unlockTakesADuration() {
        #expect(GradesLock.seconds("30m") == 1800)
        #expect(GradesLock.seconds("1h30m") == 5400)
        #expect(GradesLock.seconds("90s") == 90)
        #expect(GradesLock.seconds("1 h") == nil && GradesLock.seconds("h") == nil && GradesLock.seconds("") == nil)
        #expect(h.cli(["unlock", "--for", "soon"], gist: URL(filePath: "/nonexistent")).code == 2)
        #expect(h.cli(["unlock", "--for", "12h"], gist: URL(filePath: "/nonexistent")).code == 0)
        #expect(h.cli(["unlock", "--for", "12h1s"], gist: URL(filePath: "/nonexistent")).code == 2)
        // Unlocking asks even for a longer time; a refusal leaves it locked.
        #expect(h.cli(["unlock", "--for", "1h"], gist: URL(filePath: "/nonexistent"), gradesLocked: true).code == 5)
    }
}
