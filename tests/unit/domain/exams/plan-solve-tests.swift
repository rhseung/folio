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

    func study(_ f: Fixture, log: StudyLog = StudyLog(), cards: [StudyCard] = []) -> CourseStudy {
        CourseStudy(file: f.file, cards: cards, log: log, settings: Settings(), calendar: Calendar(identifier: .gregorian), now: at)
    }

    func item(_ kind: ExamPlanTarget.Kind) -> ExamPlanItem {
        ExamPlanItem(day: ymd("2026-11-20"), target: ExamPlanTarget(kind: kind))
    }

    @Test func aMockIsOnePastExamSetWithTheExamsTime() throws {
        let f = fixture(end: at.addingTimeInterval(75 * 60))
        let solve = try #require(study(f).solve(item(.mock), in: f.exam, seed: 1))
        #expect(solve.mode == .mock && solve.minutes == 75)
        #expect(solve.problems == f.past.problems.map(\.id))
    }

    @Test func withoutAPastExamTheMockMixesScopeProblemsAndUsesTheSetting() throws {
        let f = fixture(pastExam: false)
        let s = study(f)
        let solve = try #require(s.solve(item(.mock), in: f.exam, seed: 1))
        #expect(solve.minutes == Settings().study.mockMinutes)
        let scope = Set(s.scopeProblems(of: f.exam).map(\.problem.id))
        #expect(Set(solve.problems) == scope && solve.problems.count == 5)
    }

    @Test func mixedShufflesOnlyScopeProblems() throws {
        let f = fixture()
        let solve = try #require(study(f).solve(item(.mixed), in: f.exam, seed: 7))
        // 범위의 문제가 서술형이라 문제집 PDF로 손으로 푼다.
        #expect(solve.shuffled && solve.mode == .handwriting)
        #expect(!solve.problems.contains(f.past.problems[1].id) && solve.problems.count == 5)
    }

    @Test func wrongOpensWrongProblemsThenCards() throws {
        let f = fixture()
        let solves = [(at, ProblemSolveEvent(setId: f.exercise.id, problemId: f.exercise.problems[0].id, verdict: .wrong, basis: .key))]
        let wrong = try #require(study(f, log: StudyLog(solves: solves)).solve(item(.wrong), in: f.exam, seed: 1))
        #expect(wrong.problems == [f.exercise.problems[0].id] && !wrong.cards)

        let card = StudyCard(device: device, at: at, unitId: f.scoped.id, front: "매칭", back: "공통 끝점이 없는 변의 집합")
        let flips = [(at, CardFlipEvent(cardId: card.id, known: false))]
        let cards = try #require(study(f, log: StudyLog(flips: flips), cards: [card]).solve(item(.wrong), in: f.exam, seed: 1))
        #expect(cards.problems.isEmpty && cards.cardScope == [f.scoped.id])
        #expect(study(f).solve(item(.wrong), in: f.exam, seed: 1) == nil)
    }

    @Test func unitsAndCustomItemsAreNotSolves() {
        let f = fixture()
        let unit = ExamPlanItem(day: ymd("2026-11-20"), target: .unit(f.scoped.id))
        #expect(study(f).solve(unit, in: f.exam, seed: 1) == nil)
        #expect(study(f).solve(item(.custom), in: f.exam, seed: 1) == nil)
    }
}

private func ymd(_ text: String) -> LocalDate {
    guard let day = LocalDate(text) else { preconditionFailure(text) }
    return day
}
