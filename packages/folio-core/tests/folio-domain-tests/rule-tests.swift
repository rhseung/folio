@testable import FolioDomain
import Foundation
import Testing

/// One breaking edit per declared rule: each must be the violation a save would refuse.
struct RuleTests {
    static let device = UUID()
    static let now = Date(timeIntervalSince1970: 1_793_149_200)

    static let session = Session(device: device, at: now, week: 2, index: 1, date: now)
    static let unit = Unit(device: device, at: now, title: "트리", order: 0)
    static let component = GradeComponent(device: device, at: now, name: "과제", weight: 30)

    static var course: CourseFile {
        var exam = Exam(device: device, at: now, kind: .midterm, title: "중간고사", start: now, end: now.addingTimeInterval(3600))
        exam.plan = [ExamPlanItem(day: LocalDate(year: 2026, month: 10, day: 20)!, title: "트리 복습")]
        return CourseFile(course: Course(device: device, at: now, title: "그래프 이론"), units: [unit], sessions: [session], exams: [exam],
                          assignments: [Assignment(device: device, at: now, title: "HW1")], components: [component],
                          scores: [ScoreEntry(device: device, at: now, componentId: component.id, title: "HW1", score: 8, max: 10)],
                          attendance: [Attendance(device: device, at: now, sessionId: session.id, state: .present)],
                          problemSets: [ProblemSet(device: device, at: now, title: "연습", problems: [.init(number: "1")])])
    }

    static let courseCases: [(String, @Sendable (inout CourseFile) -> Void)] = [
        ("Course.credits", { $0.course.credits = -1 }),
        ("Course.schedule", { $0.course.schedule = [ClassTime(weekday: 1, startMinute: 600, endMinute: 600)] }),
        ("Course.title.empty", { $0.course.title = " " }),
        ("Unit.title.empty", { $0.units[0].title = "" }),
        ("Unit.parentId", { $0.units[0].parentId = UUID() }),
        ("Session.pages", { $0.sessions[0].materials = [SessionMaterial(materialId: UUID(), firstPage: 12, lastPage: 3)] }),
        ("Exam.title.empty", { $0.exams[0].title = "" }),
        ("Exam.time", { $0.exams[0].end = $0.exams[0].start }),
        ("Exam.scopeUnitIds", { $0.exams[0].scopeUnitIds = [UUID()] }),
        ("Exam.scopeUnitIds~Unit.examIds", { $0.exams[0].scopeUnitIds = [unit.id] }),
        ("Session.unitIds~Unit.sessionIds", { $0.units[0].sessionIds = [session.id] }),
        ("ExamPlanItem.title.empty", { $0.exams[0].plan[0].title = "" }),
        ("ExamPlanItem.target", { $0.exams[0].plan[0].target = ExamPlanTarget(kind: .problemSet, id: UUID()) }),
        ("Assignment.title.empty", { $0.assignments[0].title = "" }),
        ("Assignment.componentId", { $0.assignments[0].componentId = UUID() }),
        ("Assignment.componentGroup", { $0.assignments[0].componentGroup = "Reports" }),
        ("GradeComponent.weight", { $0.components[0].weight = -10 }),
        ("GradeComponent.count", { $0.components[0].aggregation = .bestOf(0) }),
        ("GradeComponent.expected", { $0.components[0].expectedCount = 0 }),
        ("GradeComponent.single", { f in
            f.components[0].aggregation = .single
            f.scores.append(ScoreEntry(device: device, at: now, componentId: component.id, title: "HW2", score: 9, max: 10))
        }),
        ("ScoreEntry.max", { $0.scores[0].max = 0 }),
        ("ScoreEntry.examId", { $0.scores[0].examId = UUID() }),
        ("Attendance.cancelled", { $0.sessions[0].isCancelled = true }),
        ("Attendance.sessionId", { $0.attendance[0].sessionId = UUID() }),
        ("ProblemSet.problems", { $0.problemSets[0].problems = [] }),
        ("ProblemSet.units", { $0.problemSets[0].problems[0].unitIds = [UUID()] }),
        ("GradePolicy.minAttendanceRatio", { $0.policy.minAttendanceRatio = 75 }),
        ("CourseFile.id", { $0.units.append($0.units[0]) }),
    ]

    @Test(arguments: courseCases.indices)
    func courseRule(_ i: Int) {
        let (rule, breakIt) = Self.courseCases[i]
        let before = Self.course
        #expect(before.violations.isEmpty, "\(before.violations)")
        var after = before
        breakIt(&after)
        let rules = Set(CourseFile.model.violations(in: after).subtracting(before.violations).map(\.rule.name))
        #expect(rule == "CourseFile.id" ? rules.contains("Unit.id") : rules.contains(rule), "\(rule): \(rules)")
    }

    @Test func courseRulesThatReadTheCatalog() {
        let grade = LetterGrade(device: Self.device, at: Self.now, symbol: "P", points: nil, countsInGpa: false, countsInCredits: true)
        let world = World(catalog: Catalog(letterGrades: [grade]), transcript: Transcript())
        var after = Self.course
        after.course.codes = [UUID()]
        after.course.semesterId = UUID()
        after.policy.cutoffs = [GradeCutoff(grade: grade.id, minScore: 90)]
        let rules = Set(CourseFile.model.violations(in: after, world: world).map(\.rule.name))
        #expect(rules.isSuperset(of: ["Course.codes", "Course.semester", "GradePolicy.grades"]), "\(rules)")
        #expect(CourseFile.model.violations(in: after).isEmpty, "without the other files their checks pass")
    }

    @Test func semesterWeeksStayInTheTerm() {
        var s = Semester(device: Self.device, at: Self.now, year: 2026, term: .fall,
                         start: LocalDate(year: 2026, month: 9, day: 1), end: LocalDate(year: 2026, month: 12, day: 18))
        s.midtermWeek = 8
        #expect(Transcript(semesters: [s]).violations.isEmpty)
        s.finalWeek = 30
        #expect(Transcript(semesters: [s]).violations.map(\.rule.name) == ["Semester.examWeeks"])
        s.finalWeek = 16
        s.end = LocalDate(year: 2026, month: 8, day: 1)
        #expect(Set(Transcript(semesters: [s]).violations.map(\.rule.name)).contains("Semester.dates"))
    }

    @Test func settingsStayInRange() {
        #expect(Settings().violations.isEmpty)
        var s = Settings()
        s.review.dailyLimit = 0
        s.dayBoundaryMinutes = 2000
        #expect(s.violations.count == 2)
    }

    @Test func choiceAnswerIsAnOption() {
        let unit = UUID()
        var card = QuizCard(device: Self.device, at: Self.now, unitId: unit, type: .choice, category: .concept, prompt: "?", options: ["a", "b"], answer: "a")
        #expect(QuizFile(unitId: unit, cards: [card]).violations.isEmpty)
        card.answer = "c"
        #expect(QuizFile(unitId: unit, cards: [card]).violations.map(\.rule.name) == ["QuizCard.answer"])
    }

    @Test func removingAComponentTakesItsScoresAndFreesItsExams() throws {
        var f = Self.course
        f.exams[0].componentId = Self.component.id
        try f.remove(GradeComponent.self, Self.component.id)
        #expect(f.scores.isEmpty)
        #expect(f.exams[0].componentId == nil)
        #expect(f.violations.isEmpty)
    }
}
