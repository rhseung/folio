import FolioCore
import FolioDomain
import Foundation
import PropertyBased
import Testing

struct SolvePickTests {
    let device = UUID()
    let at = Date(timeIntervalSince1970: 1_790_000_000)
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }

    func time(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)) ?? .distantPast
    }

    struct Fixture {
        var file: CourseFile
        var units: [FolioDomain.Unit]
        var past: ProblemSet
        var exercise: ProblemSet
    }

    // 단원 둘에 기출 셋과 연습 둘이다. 연습 문제가 앞 단원, 기출이 뒤 단원에 먼저 있어 단원 순 정렬이 드러난다.
    func fixture() -> Fixture {
        let units = [
            FolioDomain.Unit(device: device, at: at, title: "매칭", order: 0),
            FolioDomain.Unit(device: device, at: at, title: "연결도", order: 1),
        ]
        let past = ProblemSet(
            device: device, at: at, title: "2022 중간", source: .pastExam,
            problems: [
                Problem(number: "1", unitIds: [units[1].id]), Problem(number: "2", unitIds: [units[0].id]),
                Problem(number: "3", unitIds: [units[1].id]),
            ])
        let exercise = ProblemSet(
            device: device, at: at, title: "연습 1", source: .exercise,
            problems: [Problem(number: "1", unitIds: [units[0].id]), Problem(number: "2", unitIds: [units[1].id])])
        let file = CourseFile(course: Course(device: device, at: at, title: "그래프 이론"), units: units, problemSets: [past, exercise])
        return Fixture(file: file, units: units, past: past, exercise: exercise)
    }

    func study(
        _ f: Fixture, solves: [(at: Date, event: ProblemSolveEvent)] = [], cards: [StudyCard] = [],
        flips: [(at: Date, event: CardFlipEvent)] = []
    ) -> CourseStudy {
        CourseStudy(
            file: f.file, cards: cards, log: StudyLog(solves: solves, flips: flips), settings: Settings(), calendar: calendar,
            now: time(20, 12))
    }

    func solve(_ set: ProblemSet, _ i: Int, _ v: Verdict) -> (at: Date, event: ProblemSolveEvent) {
        (time(19, 10), ProblemSolveEvent(setId: set.id, problemId: set.problems[i].id, verdict: v, basis: .solution))
    }

    @Test func byUnitKeepsTheOutlineOrderThenTheSetOrder() {
        let f = fixture()
        let picked = SolvePick().pick(from: study(f), seed: 1).map(\.problem.id)
        #expect(
            picked == [
                f.past.problems[1].id, f.exercise.problems[0].id, f.past.problems[0].id, f.past.problems[2].id,
                f.exercise.problems[1].id,
            ])
    }

    @Test func filtersCombine() {
        let f = fixture()
        let s = study(f, solves: [solve(f.past, 0, .wrong), solve(f.past, 2, .correct)])
        #expect(SolvePick(filter: .wrong).pick(from: s, seed: 1).map(\.problem.id) == [f.past.problems[0].id])
        #expect(SolvePick(filter: .untried, sources: [.pastExam]).pick(from: s, seed: 1).map(\.problem.id) == [f.past.problems[1].id])
        #expect(SolvePick(units: [f.units[0].id], count: 1).pick(from: s, seed: 1).count == 1)
    }

    // 무작위 조건에서도 고른 문제는 모두 조건에 맞고, 같은 씨앗이면 같은 순서이며, 개수를 넘지 않는다.
    @Test func pickedProblemsAlwaysMatch() async {
        let f = fixture()
        let s = study(f, solves: [solve(f.past, 0, .wrong), solve(f.exercise, 1, .correct)])
        await propertyCheck(input: Gen.int(in: 0...2), Gen.int(in: 0...3), Gen.bool, Gen.int(in: 0...6), Gen.int(in: 1...999)) {
            filter, unit, shuffled, count, seed in
            let pick = SolvePick(
                filter: [SolvePick.Filter.wrong, .untried, .all][filter], units: unit < 2 ? [f.units[unit].id] : [],
                count: count == 0 ? nil : count, order: shuffled ? .shuffled : .byUnit)
            let picked = pick.pick(from: s, seed: UInt64(seed))
            #expect(picked.allSatisfy(pick.matches))
            #expect(picked.map(\.problem.id) == pick.pick(from: s, seed: UInt64(seed)).map(\.problem.id))
            #expect(Set(picked.map(\.problem.id)).count == picked.count)
            if count == 0 { #expect(picked.count == s.allProblems.filter(pick.matches).count) } else { #expect(picked.count <= count) }
        }
    }

    @Test func examReadinessCountsTheScopeOnly() {
        let f = fixture()
        var file = f.file
        var exam = Exam(device: device, at: at, title: "중간고사", start: time(25, 10), end: time(25, 12))
        exam.scopeUnitIds = [f.units[0].id]
        file.exams = [exam]
        let s = CourseStudy(
            file: file, cards: [], log: StudyLog(solves: [solve(f.past, 1, .correct)]), settings: Settings(), calendar: calendar,
            now: time(20, 12))
        let r = s.readiness(for: exam)
        #expect(r.units == 1 && r.problemsTotal == 2 && r.problemsSolved == 1)
        #expect(s.nextExam(now: time(20, 12), calendar: calendar)?.id == exam.id)
        #expect(s.nextExam(now: time(26, 12), calendar: calendar) == nil)
    }

    @Test func theFlipDeckPutsUnknownCardsFirst() {
        let f = fixture()
        let cards = ["가", "나", "다"].map { StudyCard(device: device, at: at, unitId: f.units[0].id, front: $0, back: "") }
        let flips = [
            (time(19, 10), CardFlipEvent(cardId: cards[0].id, known: true)),
            (time(19, 11), CardFlipEvent(cardId: cards[2].id, known: false)),
        ]
        let deck = study(f, cards: cards, flips: flips).flipDeck(unit: f.units[0].id).map(\.card.front)
        #expect(deck == ["다", "나", "가"])
    }

    @Test func problemNumbersReadRanges() {
        #expect(ProblemSet.numbers(from: "1-3, 5 8a, 2") == ["1", "2", "3", "5", "8a"])
        #expect(ProblemSet.numbers(from: "") == [])
        #expect(ProblemSet.numbers(from: "1-100000") == ["1-100000"])
    }
}
