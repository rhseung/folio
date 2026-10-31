@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

struct GradesSetupTests {
    let h = Harness()
    let gt = Harness.graphTheory
    static let fall = UUID(uuidString: "5E4F1A00-0000-4000-8000-000000000003")!
    static let component = UUID(uuidString: "B0000000-0000-4000-8000-000000000001")!
    static let quiz = UUID(uuidString: "B0000000-0000-4000-8000-000000000002")!
    static let score = UUID(uuidString: "B0000000-0000-4000-8000-000000000003")!
    static let code = UUID(uuidString: "B0000000-0000-4000-8000-000000000010")!
    static let grade = UUID(uuidString: "B0000000-0000-4000-8000-000000000011")!
    static let person = UUID(uuidString: "B0000000-0000-4000-8000-000000000012")!

    static let addComponent = ["component", "add", "EC4207", "과제", "--weight", "30", "--id", component.uuidString]
    static let addQuiz = ["component", "add", "EC4207", "퀴즈", "--weight", "20", "--id", quiz.uuidString]
    static let addScore = ["score", "add", "EC4207", "--component", "과제", "--title", "HW1", "--score", "9", "--max", "10", "--id", score.uuidString]

    var catalog: Catalog {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        return Catalog(codes: [CourseCode(id: Self.code, device: h.device, at: at, prefix: "EC")],
                       letterGrades: [LetterGrade(id: Self.grade, device: h.device, at: at, symbol: "A+", points: 4.5, countsInGpa: true, countsInCredits: true)],
                       people: [Person(id: Self.person, device: h.device, at: at, name: "김교수")])
    }

    /// A catalog file both copies load in setup, since course codes and grades are looked up by name.
    func catalogFile() throws -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: "catalog-\(UUID().uuidString).json")
        try JSONEncoder.folio.encode(catalog).write(to: url)
        return url.path
    }

    // MARK: Setup

    @Test func catalogSet() throws {
        let file = try catalogFile()
        try h.expectSame(["catalog", "set", "--file", file]) { _ in CatalogSet(catalog: catalog) }
    }

    @Test func settingsSet() throws {
        var settings = Settings()
        settings.dayBoundaryMinutes = 5 * 60
        let url = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString).json")
        try JSONEncoder.folio.encode(settings).write(to: url)
        try h.expectSame(["settings", "set", "--file", url.path]) { _ in SettingsSet(settings: settings) }
    }

    @Test func semesterAdd() throws {
        let id = UUID()
        try h.expectSame(["semester", "add", "2027", "spring", "--start", "2027-03-02", "--id", id.uuidString]) { _ in
            SemesterAdd(id: id, year: 2027, term: .spring, start: LocalDate("2027-03-02"))
        }
    }

    @Test func semesterSet() throws {
        try h.expectSame(["semester", "set", "2026-3", "--midterm-week", "8"]) { _ in SemesterSet(semester: Self.fall, midtermWeek: .set(8)) }
    }

    static let credited = UUID(uuidString: "CED17ED0-0000-4000-8000-000000000001")!
    static let creditedCourse = UUID(uuidString: "CED17ED0-0000-4000-8000-000000000002")!
    static let creditedSetup = [["semester", "add", "2024", "credited", "--credited-hours", "9", "--id", credited.uuidString]]
    static let creditedRecord = creditedSetup + [["transcript", "add", "2024 credited", "군 복무 인정", "--credits", "9", "--id", creditedCourse.uuidString]]

    @Test func creditedSemester() throws {
        let id = UUID()
        try h.expectSame(["semester", "add", "2024", "credited", "--credited-hours", "9", "--id", id.uuidString]) { _ in
            SemesterAdd(id: id, year: 2024, term: .credited, creditedHours: 9)
        }
        try h.expectSame(["semester", "set", "2024 credited", "--credited-hours", "none"], setup: Self.creditedSetup) { _ in
            SemesterSet(semester: Self.credited, creditedHours: .set(nil))
        }
    }

    @Test func transcriptRecord() throws {
        try h.expectSame(["transcript", "add", "2024 credited", "군 복무 인정", "--credits", "9", "--id", Self.creditedCourse.uuidString],
                         setup: Self.creditedSetup) { _ in
            TranscriptAdd(id: Self.creditedCourse, semester: Self.credited, title: "군 복무 인정", credits: 9)
        }
        try h.expectSame(["transcript", "set", "군 복무 인정", "--credits", "6", "--mode", "absolute"], setup: Self.creditedRecord) { _ in
            TranscriptSet(course: Self.creditedCourse, credits: .set(6), mode: .set(.absolute))
        }
        try h.expectSame(["transcript", "rm", "군 복무 인정", "--yes"], setup: Self.creditedRecord) { _ in
            TranscriptRemove(course: Self.creditedCourse)
        }
    }

    @Test func transcriptLeavesFolderCourses() throws {
        let r = h.cli(["transcript", "rm", "EC4207", "--yes"], gist: try Harness.fixtureCopy())
        #expect(r.code != 0)
        #expect(r.err.contains("과목 폴더가 있는 과목"))
    }

    @Test func courseAdd() throws {
        let id = UUID()
        try h.expectSame(["course", "add", "EC", "4208-01", "네트워크", "--semester", "2026-3", "--id", id.uuidString],
                         setup: [["catalog", "set", "--file", try catalogFile()]]) { _ in
            CourseAdd(id: id, semester: Self.fall, title: "네트워크", code: Self.code, number: "4208-01", credits: 3, mode: .relative)
        }
    }

    @Test func courseRename() throws {
        try h.expectSame(["course", "rename", "EC4207", "--code", "EC", "--number", "4207-01", "--title", "그래프 이론과 응용", "--yes"],
                         setup: [["catalog", "set", "--file", try catalogFile()]]) { _ in
            CourseRename(course: gt, title: "그래프 이론과 응용", codes: [Self.code], number: "4207-01")
        }
    }

    @Test func courseSet() throws {
        try h.expectSame(["course", "set", "EC4207", "--credits", "4", "--grade", "A+", "--instructor", "김교수", "--sharing-approved", "true"],
                         setup: [["catalog", "set", "--file", try catalogFile()]]) { _ in
            CourseSet(course: gt, [.credits(4), .finalGrade(Self.grade), .instructors([Self.person]), .sharingApproved(true)])
        }
    }

    @Test func courseSetIcon() throws {
        try h.expectSame(["course", "set", "EC4207", "--icon", "function"]) { _ in CourseSet(course: gt, [.icon("function")]) }
        // none clears the icon, and the key goes with it.
        try h.expectSame(["course", "set", "EC4207", "--icon", "none"], setup: [["course", "set", "EC4207", "--icon", "function"]]) { _ in
            CourseSet(course: gt, [.icon(nil)])
        }
    }

    @Test func courseSetColor() throws {
        try h.expectSame(["course", "set", "EC4207", "--color", "teal"]) { _ in CourseSet(course: gt, [.color("teal")]) }
        try h.expectSame(["course", "set", "EC4207", "--color", "none"], setup: [["course", "set", "EC4207", "--color", "teal"]]) { _ in
            CourseSet(course: gt, [.color("")])
        }
        // Colors come from the presets only.
        #expect(h.cli(["course", "set", "EC4207", "--color", "#FF0000"], gist: try Harness.fixtureCopy()).code == 2)
    }

    @Test func graduationSet() throws {
        try h.expectSame(["requirement", "set", "--admission-year", "2023"]) { _ in GraduationSet(rule: GraduationRule(admissionYear: 2023)) }
    }

    // MARK: Grades

    @Test func componentAdd() throws {
        try h.expectSame(Self.addComponent) { _ in
            ComponentAdd(id: Self.component, course: gt, name: "과제", weight: 30)
        }
    }

    @Test func componentSet() throws {
        try h.expectSame(["component", "set", "EC4207/과제", "--weight", "25", "--group", "none"], setup: [Self.addComponent]) { _ in
            ComponentSet(course: gt, component: Self.component, weight: .set(25), group: .set(nil))
        }
    }

    @Test func componentRemove() throws {
        try h.expectSame(["component", "rm", "EC4207/과제", "--yes"], setup: [Self.addComponent, Self.addScore]) { _ in
            ComponentRemove(course: gt, component: Self.component)
        }
    }

    @Test func componentMove() throws {
        try h.expectSame(["component", "move", "EC4207/퀴즈", "--up"], setup: [Self.addComponent, Self.addQuiz]) { _ in
            ComponentMove(course: gt, component: Self.quiz, by: -1)
        }
    }

    @Test func policySet() throws {
        try h.expectSame(["component", "policy", "EC4207", "--lates-per-absence", "3"]) { _ in
            var p = GradePolicy()
            p.latesPerAbsence = 3
            return PolicySet(course: gt, policy: p)
        }
    }

    @Test func scoreAdd() throws {
        try h.expectSame(Self.addScore, setup: [Self.addComponent]) { _ in
            ScoreAdd(id: Self.score, course: gt, component: Self.component, title: "HW1", score: 9, max: 10)
        }
    }

    @Test func scoreSet() throws {
        try h.expectSame(["score", "set", "EC4207/HW1", "--value", "10", "--mean", "7.5", "--excused", "true"], setup: [Self.addComponent, Self.addScore]) { _ in
            ScoreSet(course: gt, score: Self.score, value: .set(10), mean: .set(7.5), excused: .set(true))
        }
    }

    @Test func scoreRemove() throws {
        try h.expectSame(["score", "rm", "EC4207/HW1", "--yes"], setup: [Self.addComponent, Self.addScore]) { _ in
            ScoreRemove(course: gt, score: Self.score)
        }
    }

    @Test func removingAsksFirstWithoutATerminal() throws {
        let gist = try Harness.fixtureCopy()
        for line in [Self.addComponent, Self.addScore] { #expect(h.cli(line, gist: gist).code == 0) }
        #expect(h.cli(["score", "rm", "EC4207/HW1"], gist: gist).code == Exit.needsConfirmation.rawValue)
        #expect(try h.file(GISTStore(url: gist)).scores.count == 1)
    }

    @Test func gpaRunsOnTheFixture() throws {
        let r = h.cli(["gpa"], gist: try Harness.fixtureCopy())
        #expect(r.code == 0)
        #expect(r.out.contains("누적"))
        #expect(h.cli(["gpa", "--json"], gist: try Harness.fixtureCopy()).out.hasPrefix("["))
    }

    @Test func listsAndShowsRun() throws {
        let gist = try Harness.fixtureCopy()
        for line in [Self.addComponent, Self.addScore] { #expect(h.cli(line, gist: gist).code == 0) }
        for line in [["score", "list", "EC4207"], ["component", "list", "EC4207"], ["semester", "list"], ["semester", "show"],
                     ["course", "list"], ["course", "show", "EC4207"], ["requirement", "show"], ["catalog", "show"], ["settings", "show"]] {
            let r = h.cli(line, gist: gist)
            #expect(r.code == 0, "\(line): \(r.err)")
        }
        #expect(h.cli(["course", "list"], gist: gist).out.contains("EC4207"))
        #expect(h.cli(["component", "list", "EC4207"], gist: gist).out.contains("███░░░░░░░ 30%"))
    }
}
