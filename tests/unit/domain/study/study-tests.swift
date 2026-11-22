import FolioCore
import FolioDomain
import Foundation
import PropertyBased
import Testing

struct WrongFlowTests {
    let d1 = ymd("2026-11-17")
    let d2 = ymd("2026-11-18")
    let d3 = ymd("2026-11-19")

    @Test func startsUntriedAndStaysCleanWhenRight() {
        #expect(WrongFlow.status([]) == .untried)
        #expect(WrongFlow.status([(d1, true), (d2, true)]) == .neverWrong)
    }

    @Test func rightOnTheSameDayOnlyAsksToCheckAgain() {
        #expect(WrongFlow.status([(d1, false)]) == .open(since: d1))
        #expect(WrongFlow.status([(d1, false), (d1, true)]) == .recheck(since: d1))
        #expect(WrongFlow.status([(d1, false), (d1, true), (d1, true)]) == .recheck(since: d1))
        #expect(WrongFlow.status([(d1, false), (d1, true), (d2, true)]) == .resolved(on: d2))
    }

    @Test func onlyARightAnswerOnTheWrongDayStaysForRecheck() {
        #expect(WrongFlow.staysRecheck(.open(since: d1), rightOn: d1))
        #expect(WrongFlow.staysRecheck(.recheck(since: d1), rightOn: d1))
        #expect(!WrongFlow.staysRecheck(.open(since: d1), rightOn: d2))
        #expect(!WrongFlow.staysRecheck(.untried, rightOn: d1))
        #expect(!WrongFlow.staysRecheck(.resolved(on: d1), rightOn: d1))
    }

    @Test func rightOnALaterDayLeavesTheWrongList() {
        #expect(WrongFlow.status([(d1, false), (d2, true)]) == .resolved(on: d2))
        #expect(WrongFlow.status([(d1, false), (d2, true), (d3, false)]) == .open(since: d3))
        #expect(WrongFlow.status([(d1, false), (d2, false), (d2, true)]) == .recheck(since: d2))
    }
}

struct ReadinessTests {
    func item(_ v: Verdict?, _ basis: GradeBasis = .key, _ status: WrongStatus = .neverWrong) -> Readiness.Item {
        Readiness.Item(verdict: v, basis: v == nil ? nil : basis, status: v == nil ? .untried : status)
    }

    @Test func fewProblemsComesFirst() {
        #expect(Readiness.state([item(.correct), item(.correct)], readyScore: 0.8, minProblems: 3) == .fewProblems)
        #expect(Readiness.state([], readyScore: 0.8, minProblems: 3) == .fewProblems)
    }

    @Test func noVerdictUntilSomethingIsJudged() {
        #expect(Readiness.state([item(nil), item(nil), item(nil)], readyScore: 0.8, minProblems: 3) == .noVerdict)
        #expect(Readiness.score([item(nil)]) == nil)
    }

    // 넷 중 하나만 Claude가 맞음으로 채점한 단원은 점수가 낮아도 약함이 아니라 판정 부족이다.
    @Test func fewJudgedProblemsAreNotWeak() {
        let items = [item(.correct, .claude), item(nil), item(nil), item(nil)]
        #expect(Readiness.state(items, readyScore: 0.8, minProblems: 3) == .fewVerdicts)
        #expect(Readiness.score(items) == 0.5 / 3.5)
        let judged = [item(.correct), item(.wrong), item(.correct), item(nil)]
        #expect(Readiness.state(judged, readyScore: 0.8, minProblems: 3) == .weak)
    }

    @Test func unsolvedProblemsCountAsZero() {
        let items = [item(.correct), item(.correct), item(.correct), item(nil)]
        #expect(Readiness.score(items) == 0.75)
        #expect(Readiness.state(items, readyScore: 0.8, minProblems: 3) == .weak)
        #expect(Readiness.state(Array(items.prefix(3)), readyScore: 0.8, minProblems: 3) == .ready)
    }

    // 맞음 1(무게 1) + 틀림 0(무게 0.5) = 1 / 1.5
    @Test func claudeWithoutASolutionWeighsHalf() {
        let score = Readiness.score([item(.correct), item(.wrong, .claude, .open(since: ymd("2026-11-17")))])
        #expect(abs((score ?? 0) - 2.0 / 3.0) < 1e-9)
    }

    @Test func aWrongOrRecheckBlocksReady() {
        let day = ymd("2026-11-17")
        let recheck = [item(.correct), item(.correct), item(.correct), item(.correct), item(.correct, .key, .recheck(since: day))]
        #expect(Readiness.score(recheck) == 1)
        #expect(Readiness.state(recheck, readyScore: 0.8, minProblems: 3) == .weak)
    }

    static let verdicts = Gen.int(in: 0...3).array(of: 1...12)

    static func verdict(_ i: Int) -> Verdict? { i < 3 ? [Verdict.wrong, .partial, .correct][i] : nil }

    @Test func aBetterVerdictNeverLowersTheScore() async {
        await propertyCheck(input: Self.verdicts, Gen.int(in: 0...11), Gen.bool) { raw, pick, claude in
            let items = raw.map { Readiness.Item(verdict: Self.verdict($0), basis: claude ? .claude : .key) }
            let i = pick % items.count
            var better = items
            let now = raw[i] == 3 ? -1 : raw[i]
            guard now < 2 else { return }
            better[i].verdict = Self.verdict(now + 1)
            better[i].basis = items[i].basis
            #expect((Readiness.score(better) ?? 0) + 1e-9 >= (Readiness.score(items) ?? 0))
        }
    }

    @Test func theScoreStaysBetweenZeroAndOne() async {
        await propertyCheck(input: Self.verdicts, Gen.bool) { raw, claude in
            let items = raw.map { Readiness.Item(verdict: Self.verdict($0), basis: claude ? .claude : .key) }
            if let s = Readiness.score(items) { #expect(s >= 0 && s <= 1) }
        }
    }
}

struct CourseStudyTests {
    let device = UUID()
    let at = Date(timeIntervalSince1970: 1_790_000_000)
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }

    func time(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    struct Fixture {
        var file: CourseFile
        var set: ProblemSet
        var unit: FolioDomain.Unit
    }

    func fixture() -> Fixture {
        var unit = FolioDomain.Unit(device: device, at: at, title: "매칭", order: 0)
        let lecture = UUID()
        unit.lecturePages = [UnitPages(materialId: lecture, firstPage: 3, lastPage: 6)]
        let set = ProblemSet(
            device: device, at: at, title: "2022 중간", source: .pastExam,
            problems: (1...3).map { Problem(number: "\($0)", unitIds: [unit.id]) })
        let file = CourseFile(course: Course(device: device, at: at, title: "그래프 이론"), units: [unit], problemSets: [set])
        return Fixture(file: file, set: set, unit: unit)
    }

    func solve(_ set: ProblemSet, _ i: Int, _ v: Verdict, at date: Date, basis: GradeBasis = .solution) -> (
        at: Date, event: ProblemSolveEvent
    ) {
        (date, ProblemSolveEvent(setId: set.id, problemId: set.problems[i].id, verdict: v, basis: basis))
    }

    // 하루 경계는 새벽 4시다. 03:59의 풀이는 전날 공부일이고 04:00부터 다음 공부일이다.
    @Test func theDayBoundaryDecidesRecheck() {
        let f = fixture()
        let (file, set) = (f.file, f.set)
        let wrong = solve(set, 0, .wrong, at: time(17, 23))
        let before = CourseStudy(
            file: file, cards: [], log: StudyLog(solves: [wrong, solve(set, 0, .correct, at: time(18, 3, 59))]), settings: Settings(),
            calendar: calendar, now: time(18, 12))
        #expect(before.problems[set.problems[0].id]?.status == .recheck(since: ymd("2026-11-17")))

        let after = CourseStudy(
            file: file, cards: [], log: StudyLog(solves: [wrong, solve(set, 0, .correct, at: time(18, 4))]), settings: Settings(),
            calendar: calendar, now: time(18, 12))
        #expect(after.problems[set.problems[0].id]?.status == .resolved(on: ymd("2026-11-18")))
    }

    // 전날 23시에 틀린 문제를 새벽 3시 59분에 맞히면 아직 같은 공부일이라 "다시 확인"을 알리고, 4시에 맞히면 알리지 않는다.
    @Test func theRecheckNoticeFollowsTheDayBoundary() throws {
        let f = fixture()
        let study = CourseStudy(
            file: f.file, cards: [], log: StudyLog(solves: [solve(f.set, 0, .wrong, at: time(17, 23))]), settings: Settings(),
            calendar: calendar, now: time(18, 3, 59))
        let status = try #require(study.problems[f.set.problems[0].id]?.status)
        let day = { (date: Date) in Settings().studyDay(of: date, calendar: calendar) }
        #expect(WrongFlow.staysRecheck(status, rightOn: day(time(18, 3, 59))))
        #expect(!WrongFlow.staysRecheck(status, rightOn: day(time(18, 4))))
    }

    @Test func aChangedVerdictIsFinalAndKeepsItsDay() {
        let f = fixture()
        let (file, set, unit) = (f.file, f.set, f.unit)
        let first = solve(set, 0, .wrong, at: time(17, 10))
        let log = StudyLog(
            solves: [first, solve(set, 1, .correct, at: time(17, 11)), solve(set, 2, .correct, at: time(17, 12))],
            changes: [(time(19, 9), ProblemVerdictEvent(attemptId: first.event.id, verdict: .correct))])
        let study = CourseStudy(file: file, cards: [], log: log, settings: Settings(), calendar: calendar, now: time(19, 12))
        let record = study.problems[set.problems[0].id]
        #expect(record?.last?.verdict == .correct && record?.last?.basis == .user && record?.status == .neverWrong)
        #expect(study.readiness(of: unit.id).state == .ready)
    }

    @Test func progressCountsPagesInTheUnitsRange() throws {
        let f = fixture()
        let (file, set, unit) = (f.file, f.set, f.unit)
        let lecture = try #require(unit.lecturePages.first?.materialId)
        let views = [3, 4, 9].map { (at, PageViewEvent(materialId: lecture, page: $0)) }
        let log = StudyLog(solves: [solve(set, 0, .partial, at: time(17, 10))], views: views)
        let study = CourseStudy(file: file, cards: [], log: log, settings: Settings(), calendar: calendar, now: time(17, 12))
        let p = study.progress(of: unit, notes: 1)
        #expect(p.pagesSeen == 2 && p.pagesTotal == 4)
        #expect(p.problemsSolved == 1 && p.problemsTotal == 3 && p.problemsWrong == 1)
        #expect(p.readiness.state == .fewVerdicts && p.readiness.pastExam == 3)
        #expect(study.missingProblems(of: unit.id) == 0)
        #expect(study.missingProblems(of: UUID()) == Settings().study.minProblems)
    }

    @Test func cardsFollowTheSameRule() {
        let f = fixture()
        let (file, unit) = (f.file, f.unit)
        let card = StudyCard(device: device, at: at, unitId: unit.id, front: "매칭", back: "공통 끝점이 없는 변의 집합")
        let flips = [
            (time(17, 22), CardFlipEvent(cardId: card.id, known: false)), (time(18, 2), CardFlipEvent(cardId: card.id, known: true)),
        ]
        let study = CourseStudy(
            file: file, cards: [card], log: StudyLog(flips: flips), settings: Settings(), calendar: calendar, now: time(18, 3))
        #expect(study.cards[card.id]?.status == .recheck(since: ymd("2026-11-17")))
        #expect(study.progress(of: unit, notes: 0).cardsUnknown == 1)
    }
}

struct CardSourceTests {
    let card: StudyCard = {
        var c = StudyCard(device: UUID(), at: .distantPast, unitId: UUID(), front: "매칭", back: "공통 끝점이 없는 변의 집합", source: .note)
        c.noteBlockHash = StudyCard.blockHash("> [!definition] 매칭\n> 공통 끝점이 없는 변의 집합 ^m1")
        return c
    }()

    @Test func onlyAChangedOrMissingBlockIsChanged() {
        #expect(!card.sourceChanged(block: "> [!definition] 매칭\n> 공통 끝점이 없는 변의 집합 ^m1\n"))
        #expect(card.sourceChanged(block: "> [!definition] 매칭\n> 끝점을 나누지 않는 변의 집합 ^m1"))
        #expect(card.sourceChanged(block: nil))
    }

    @Test func handMadeCardsNeverChange() {
        let plain = StudyCard(device: UUID(), at: .distantPast, unitId: UUID(), front: "a", back: "b")
        #expect(!plain.sourceChanged(block: nil))
    }
}

private func ymd(_ text: String) -> LocalDate {
    guard let day = LocalDate(text) else { preconditionFailure(text) }
    return day
}
