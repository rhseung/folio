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
    static let creditedSetup = [["semester", "add", "2024", "credited", "--source", "군 복무", "--credited-hours", "9", "--id", credited.uuidString]]

    @Test func creditedSemester() throws {
        let id = UUID()
        try h.expectSame(["semester", "add", "2024", "credited", "--source", "군 복무", "--credited-hours", "9", "--id", id.uuidString]) { _ in
            SemesterAdd(id: id, year: 2024, term: .credited, creditedHours: 9, source: "군 복무")
        }
        try h.expectSame(["semester", "set", "2024 credited", "--credited-hours", "none"], setup: Self.creditedSetup) { _ in
            SemesterSet(semester: Self.credited, creditedHours: .set(nil))
        }
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["semester", "add", "2024", "credited"], gist: gist).err.contains("출처"))
        #expect(h.cli(["semester", "add", "2024", "credited", "--source", "영재고 AP"], gist: gist).code != 0)  // the fixture's source
        for line in Self.creditedSetup { #expect(h.cli(line, gist: gist).code == 0) }
        #expect(FileManager.default.fileExists(atPath: gist.appending(path: "_Credited/군 복무").path))
    }

    /// Renaming the source renames `_Credited/<source>`, through moves.jsonl.
    @Test func creditedSource() throws {
        try h.expectSame(["semester", "source", "영재고 AP", "영재고 AP 과정", "--yes"]) { _ in
            SemesterSource(semester: UUID(uuidString: "5E4F1A00-0000-4000-8000-0000000000C1")!, source: "영재고 AP 과정")
        }
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["semester", "source", "영재고 AP", "영재고 AP 과정", "--yes"], gist: gist).code == 0)
        #expect(FileManager.default.fileExists(atPath: gist.appending(path: "_Credited/영재고 AP 과정/GS1101 일반물리학 및 연습 I/.folio/course.json").path))
        #expect(try GISTStore(url: gist).courseStores().contains { $0.url.lastPathComponent == "GS1101 일반물리학 및 연습 I" })
    }

    /// A refused source moves nothing: on a regular term the folder that would move is the whole semester's.
    @Test func refusedSourceLeavesFolders() throws {
        let gist = try Harness.fixtureCopy()
        func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: gist.appending(path: path).path) }
        let fall = try FileManager.default.contentsOfDirectory(atPath: gist.appending(path: "2026-3").path).sorted()
        #expect(h.cli(["semester", "source", "2026-3", "가을", "--yes"], gist: gist).code != 0)  // only credited terms have one
        #expect(try FileManager.default.contentsOfDirectory(atPath: gist.appending(path: "2026-3").path).sorted() == fall)
        #expect(!exists("_Credited/가을"))
        #expect(h.cli(["semester", "source", "영재고 AP", "영재고/AP", "--yes"], gist: gist).code != 0)
        #expect(exists("_Credited/영재고 AP/GS1101 일반물리학 및 연습 I"))

        let store = GISTStore(url: gist)
        var doc = try store.loadTranscript()
        doc.model.semesters.append(Semester(device: h.device, at: h.now, year: 2024, term: .credited, source: "군 복무"))
        try store.save(doc)
        try FileManager.default.createDirectory(at: gist.appending(path: "_Credited/군 복무"), withIntermediateDirectories: true)
        #expect(h.cli(["semester", "source", "영재고 AP", "군 복무", "--yes"], gist: gist).code != 0)  // taken
        #expect(exists("_Credited/영재고 AP/GS1101 일반물리학 및 연습 I"))
        #expect(try store.loadTranscript().model.semesters.filter { $0.source == "영재고 AP" }.count == 1)
    }

    @Test func transcriptAddMakesFolder() throws {
        let line = ["transcript", "add", "군 복무", "병영 독서", "--code", "EC", "--number", "1001", "--credits", "9", "--id", Self.creditedCourse.uuidString]
        let setup = [["catalog", "set", "--file", try catalogFile()]] + Self.creditedSetup
        try h.expectSame(line, setup: setup) { _ in
            TranscriptAdd(id: Self.creditedCourse, semester: Self.credited, title: "병영 독서", code: Self.code, number: "1001", credits: 9)
        }
        let gist = try Harness.fixtureCopy()
        for l in setup + [line] { #expect(h.cli(l, gist: gist).code == 0) }
        let course = try GISTStore(url: gist).courseStores().first { $0.url.lastPathComponent == "EC1001 병영 독서" }
        #expect(try course?.load().model.course.id == Self.creditedCourse)
        #expect(course.map { (try? FileManager.default.contentsOfDirectory(atPath: $0.url.path)) == [".folio"] } == true)  // subfolders come when needed
    }

    func colloquium() -> Course {
        Course(id: Self.creditedCourse, device: h.device, at: Date(timeIntervalSince1970: 1_790_000_000), semesterId: Self.fall, title: "콜로퀴움",
               codes: [Self.code], number: "9331-01", credits: 1, gradingMode: .passFail)
    }

    @Test func transcriptMove() throws {
        try h.expectSame(["transcript", "move", "--yes"], setup: [["catalog", "set", "--file", try catalogFile()]],
                         prepare: { try Harness.unfile(colloquium(), gist: $0) }) { _ in TranscriptMove() }
        let gist = try Harness.fixtureCopy()
        try Harness.unfile(colloquium(), gist: gist)
        #expect(h.cli(["catalog", "set", "--file", try catalogFile()], gist: gist).code == 0)
        #expect(h.cli(["transcript", "move", "--yes"], gist: gist).code == 0)
        let store = GISTStore(url: gist)
        #expect(try store.loadTranscript().model.unfiledCourses.isEmpty)
        #expect(try store.allCourses().first { $0.id == Self.creditedCourse } == colloquium())
        #expect(try !String(contentsOf: store.transcriptURL, encoding: .utf8).contains("unfiledCourses"))
        #expect(h.cli(["transcript", "move", "--yes"], gist: gist).code != 0)  // nothing left

        // `cleanup undo` puts the course back where it was.
        let batch = try #require(try MoveJournal.records(in: gist).last { $0.op == .fileCourse }?.batch)
        #expect(h.cli(["cleanup", "undo", batch.uuidString, "--yes"], gist: gist).code == 0)
        #expect(try store.loadTranscript().model.unfiledCourses == [colloquium()])
        #expect(!FileManager.default.fileExists(atPath: gist.appending(path: "2026-3/EC9331 콜로퀴움").path))
    }

    /// Moving changes where a course is kept, never what it counts for: every grade figure is the same after.
    @Test func transcriptMoveKeepsGrades() throws {
        let gist = try Harness.fixtureCopy()
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let ec = CourseCode(device: h.device, at: at, prefix: "EC"), gs = CourseCode(device: h.device, at: at, prefix: "GS")

        // Invented grades: the repo is public.
        let aPlus = LetterGrade(device: h.device, at: at, symbol: "A+", points: 4.5, countsInGpa: true, countsInCredits: true)
        let b0 = LetterGrade(device: h.device, at: at, symbol: "B0", points: 3, countsInGpa: true, countsInCredits: true)
        let pass = LetterGrade(device: h.device, at: at, symbol: "S", points: nil, countsInGpa: false, countsInCredits: true)
        let major = FolioDomain.Category(device: h.device, at: at, name: "전공", group: "전공", isMajor: true, minCredits: 36)
        let basic = FolioDomain.Category(device: h.device, at: at, name: "기초", group: "기초", minCredits: 18)
        try h.direct(CatalogSet(catalog: Catalog(codes: [ec, gs], categories: [major, basic], letterGrades: [aPlus, b0, pass])), gist: gist)
        let spring = UUID(uuidString: "5E4F1A00-0000-4000-8000-000000000001")!, ap = UUID(uuidString: "5E4F1A00-0000-4000-8000-0000000000C1")!
        func course(_ title: String, _ code: CourseCode, _ number: String, _ term: UUID, _ grade: LetterGrade, _ category: FolioDomain.Category,
                    credits: Double = 3, mode: GradingMode = .relative) -> Course {
            var c = Course(device: h.device, at: at, semesterId: term, title: title, codes: [code.id], number: number, categoryIds: [category.id],
                           credits: credits, gradingMode: mode)
            c.finalGrade = grade.id
            return c
        }
        let unfiled = [
            course("알고리즘", ec, "3101-01", spring, aPlus, major),
            course("미적분학", gs, "1001-02", spring, b0, basic),
            course("콜로퀴움", gs, "9331-01", Self.fall, pass, basic, credits: 1, mode: .passFail),
            course("일반물리학 및 연습 II", gs, "1102", ap, pass, basic, mode: .passFail),
        ]
        for c in unfiled { try Harness.unfile(c, gist: gist) }

        let store = GISTStore(url: gist)
        func figures(_ courses: [Course]) throws -> [String] {
            let courses = courses.sorted { $0.id.uuidString < $1.id.uuidString }
            let semesters = try store.loadTranscript().model.semesters, catalog = try store.loadCatalog().model
            return ["\(GPACalculator.cumulative(semesters: semesters, courses: courses, catalog: catalog))",
                    "\(GPACalculator.major(courses: courses, catalog: catalog))",
                    "\(semesters.map { GPACalculator.semester($0, courses: courses, catalog: catalog) })",
                    "\(GPACalculator.graduation(semesters: semesters, courses: courses, catalog: catalog))",
                    "\(GPACalculator.categoryCredits(courses: courses, catalog: catalog).sorted { $0.key.uuidString < $1.key.uuidString })",
                    "\(RequirementAudit(courses: courses, semesters: semesters, catalog: catalog))"]
        }
        let before = try figures(store.loadTranscript().model.unfiledCourses + store.allCourses())
        try h.direct(TranscriptMove(), gist: gist)
        #expect(try store.loadTranscript().model.unfiledCourses.isEmpty)
        #expect(try store.allCourses().count == 4 + unfiled.count)
        #expect(try figures(store.allCourses()) == before)
        #expect(FileManager.default.fileExists(atPath: gist.appending(path: "_Credited/영재고 AP/GS1102 일반물리학 및 연습 II").path))
    }

    /// A credited course can't go anywhere until its term has a source.
    @Test func transcriptMoveNeedsSource() throws {
        let gist = try Harness.fixtureCopy()
        let term = UUID()
        try h.direct(CatalogSet(catalog: catalog), gist: gist)
        let store = GISTStore(url: gist)
        var doc = try store.loadTranscript()
        doc.model.semesters.append(Semester(id: term, device: h.device, at: h.now, year: 2024, term: .credited))
        try store.save(doc)
        var course = colloquium()
        course.semesterId = term
        try Harness.unfile(course, gist: gist)
        let r = h.cli(["transcript", "move", "--yes"], gist: gist)
        #expect(r.code != 0 && r.err.contains("출처"))
        #expect(try store.loadTranscript().model.unfiledCourses.count == 1)
        #expect(h.cli(["semester", "source", term.uuidString, "군 복무", "--yes"], gist: gist).code == 0)
        #expect(h.cli(["transcript", "move", "--yes"], gist: gist).code == 0)
        #expect(FileManager.default.fileExists(atPath: gist.appending(path: "_Credited/군 복무/EC9331 콜로퀴움/.folio/course.json").path))
    }

    @Test func courseAdd() throws {
        let id = UUID()
        try h.expectSame(["course", "add", "EC", "4208-01", "네트워크", "--semester", "2026-3", "--id", id.uuidString],
                         setup: [["catalog", "set", "--file", try catalogFile()]]) { _ in
            CourseAdd(id: id, code: Self.code, number: "4208-01", title: "네트워크", credits: 3, mode: .relative, semester: Self.fall)
        }
    }

    /// Left out, the semester is the one today falls in, for the command and the JSON input alike.
    @Test func courseAddInTheCurrentSemester() throws {
        let id = UUID()
        try h.expectSame(["course", "add", "EC", "4208-01", "네트워크", "--id", id.uuidString],
                         setup: [["catalog", "set", "--file", try catalogFile()]]) { _ in
            CourseAdd(id: id, code: Self.code, number: "4208-01", title: "네트워크")
        }
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["catalog", "set", "--file", try catalogFile()], gist: gist).code == 0)
        #expect(h.cli(["run", "course", "add", "--input", #"{"code":"EC","number":"4208-01","title":"네트워크","id":"\#(id)"}"#], gist: gist).code == 0)
        #expect(try ActionContext(gist: GISTStore(url: gist), device: h.device).file(id).course.semesterId == Self.fall)
    }

    @Test func courseRename() throws {
        try h.expectSame(["course", "rename", "EC4207", "--code", "EC", "--number", "4207-01", "--title", "그래프 이론과 응용", "--yes"],
                         setup: [["catalog", "set", "--file", try catalogFile()]]) { _ in
            CourseRename(course: gt, title: .set("그래프 이론과 응용"), codes: .set([Self.code]), number: .set("4207-01"))
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
        try h.expectSame(["requirement", "set", "--admission-year", "2023"]) { _ in GraduationSet(admissionYear: .set(2023)) }
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
            PolicySet(course: gt, latesPerAbsence: .set(3))
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
