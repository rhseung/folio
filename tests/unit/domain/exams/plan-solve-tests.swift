import FolioCore
import FolioDomain
import Foundation
import Testing

struct PlanSolveTests {
    let device = UUID()
    let at = Date(timeIntervalSince1970: 1_790_000_000)

    struct Fixture {
        var file: CourseFile
        var exam: Exam
        var past: ProblemSet
        var exercise: ProblemSet
        var scoped: FolioDomain.Unit
    }

    func fixture(pastExam: Bool = true, end: Date? = nil) -> Fixture {
        let scoped = FolioDomain.Unit(device: device, at: at, title: "매칭", order: 0)
        let other = FolioDomain.Unit(device: device, at: at, title: "채색", order: 1)
        let past = ProblemSet(
            device: device, at: at, title: "2022 중간", source: pastExam ? .pastExam : .exercise,
            problems: [Problem(number: "1", unitIds: [scoped.id]), Problem(number: "2", unitIds: [other.id])])
        let exercise = ProblemSet(
            device: device, at: at, title: "연습", source: .exercise,
            problems: (1...4).map { Problem(number: "\($0)", unitIds: [scoped.id]) })
        var exam = Exam(device: device, at: at, title: "중간고사", start: at, end: end)
        exam.addedScopeUnitIds = [scoped.id]
        let file = CourseFile(
            course: Course(device: device, at: at, title: "그래프 이론"), units: [scoped, other], exams: [exam], problemSets: [past, exercise])
        return Fixture(file: file, exam: exam, past: past, exercise: exercise, scoped: scoped)
    }

    func study(_ f: Fixture, log: StudyLog = StudyLog()) -> CourseStudy {
        CourseStudy(file: f.file, cards: [], log: log, settings: Settings(), calendar: Calendar(identifier: .gregorian), now: at)
    }

    func row(_ kind: PlanRow.Kind, _ f: Fixture) -> PlanRow {
        PlanRow(
            id: "row", courseId: f.file.course.id, examId: f.exam.id, kind: kind, title: "", subject: nil,
            day: LocalDate(at, in: Calendar(identifier: .gregorian)), lateFrom: nil, steps: [])
    }

    @Test func aMockIsOnePastExamSetWithTheExamsTime() throws {
        let f = fixture(end: at.addingTimeInterval(75 * 60))
        let solve = try #require(study(f).solve(row(.mock, f), seed: 1))
        #expect(solve.mode == .mock && solve.minutes == 75)
        #expect(solve.problems == f.past.problems.map(\.id))
        #expect(study(f).mockSets == 1)
    }

    @Test func withoutAPastExamTheMockMixesScopeProblemsAndUsesTheSetting() throws {
        let f = fixture(pastExam: false)
        let s = study(f)
        let solve = try #require(s.solve(row(.mock, f), seed: 1))
        #expect(solve.minutes == Settings().study.mockMinutes)
        let scope = Set(s.scopeProblems(of: f.exam).map(\.problem.id))
        #expect(Set(solve.problems) == scope && solve.problems.count == 5)
        #expect(s.mockSets == 0)
    }

    @Test func yesterdaysWrongAnswersOpenEveryWrongProblemOfTheCourse() throws {
        let f = fixture()
        // 범위 밖 단원의 오답도 과목의 오답이다.
        let solves = [
            (at, ProblemSolveEvent(setId: f.exercise.id, problemId: f.exercise.problems[0].id, verdict: .wrong, basis: .key)),
            (at, ProblemSolveEvent(setId: f.past.id, problemId: f.past.problems[1].id, verdict: .partial, basis: .solution)),
        ]
        let s = study(f, log: StudyLog(solves: solves))
        let wrong = try #require(s.wrongRow)
        #expect(wrong.kind == .wrong(PlanProgress(done: 0, total: 2)) && !wrong.isDone)
        #expect(s.solve(wrong, seed: 1)?.problems == [f.past.problems[1].id, f.exercise.problems[0].id])
        #expect(study(f).wrongRow == nil)
    }

    @Test func notesAndWrittenTasksAreNotSolves() {
        let f = fixture()
        #expect(study(f).solve(row(.note(UUID()), f), seed: 1) == nil)
        #expect(study(f).solve(row(.makeNote(unit: f.scoped.id), f), seed: 1) == nil)
        #expect(study(f).solve(row(.custom, f), seed: 1) == nil)
    }
}
