import FolioCore
import FolioDomain
import Foundation
import PropertyBased
import Testing

// 정독의 진행은 그 노트에 이은 카드 가운데 시험의 공부 기간이 시작한 뒤에 넘긴 카드다(#578 "진행").
struct ReadProgressTests {
    struct Planned {
        var course: PlanCourse
        var read: ExamPlanItem
        var cards: [StudyCard]
    }

    struct Flip {
        var card: StudyCard
        var at: Date
        var known = true
    }

    // 12/8에 놓아 기간이 12/8부터인 계획과 홀의 정리 노트의 정독 항목이다.
    func planned(cards: Int, trueFalse: Bool = false) throws -> Planned {
        var course = PlanCourse()
        let hall = course.noteId("기말 02 홀의 정리")
        let made = (0..<cards).map { course.card("카드 \($0)", note: hall, answer: trueFalse ? $0.isMultiple(of: 2) : nil) }
        let placed = try #require(
            course.study(now: PlanCourse.at(12, 8)).place(course.exam, proofs: [], settings: Settings(), calendar: PlanCourse.calendar))
        course.exam.plan = placed.plan
        course.exam.planPeriod = placed.period
        course.exam.planBasis = placed.basis
        let read = try #require(course.exam.plan.first { $0.target == .note(hall, .read) })
        return Planned(course: course, read: read, cards: made)
    }

    func flips(_ list: [Flip]) -> StudyLog {
        StudyLog(flips: list.map { (at: $0.at, event: CardFlipEvent(cardId: $0.card.id, known: $0.known)) })
    }

    @Test func readingCountsTheCardsFlippedSinceThePeriodStarted() throws {
        let p = try planned(cards: 3)
        let (course, read, cards) = (p.course, p.read, p.cards)
        // 기간 전날 넘긴 카드는 세지 않는다. 모름으로 넘긴 카드도 넘긴 카드다.
        var log = flips([
            Flip(card: cards[0], at: PlanCourse.at(12, 7, 20)), Flip(card: cards[1], at: PlanCourse.at(12, 8, 10)),
            Flip(card: cards[2], at: PlanCourse.at(12, 9, 10), known: false),
        ])
        let study = course.study(now: PlanCourse.at(12, 9, 11), log: log)
        #expect(course.exam.planPeriod?.start == PlanCourse.day(12, 8))
        #expect(study.progress(of: read) == PlanProgress(done: 2, total: 3) && !study.isDone(read))

        // 한 카드를 여러 번 넘겨도 한 장이다. 남은 한 장을 넘기면 정독이 끝난다.
        log.flips.append((PlanCourse.at(12, 9, 12), CardFlipEvent(cardId: cards[2].id, known: true)))
        #expect(course.study(now: PlanCourse.at(12, 9, 13), log: log).progress(of: read).done == 2)
        log.flips.append((PlanCourse.at(12, 9, 14), CardFlipEvent(cardId: cards[0].id, known: true)))
        let done = course.study(now: PlanCourse.at(12, 9, 15), log: log)
        #expect(done.progress(of: read) == PlanProgress(done: 3, total: 3) && done.isDone(read))
        // 줄의 단계도 같은 값을 읽는다.
        let step = done.planBoard([course.exam]).next.flatMap(\.rows).flatMap(\.steps).first { $0.item == read.id }
        #expect(step == nil)
        #expect(done.planRows(of: course.exam).flatMap(\.steps).first { $0.item == read.id }?.progress == PlanProgress(done: 3, total: 3))
    }

    @Test func aNoteWithoutCardsIsReadByCheckingIt() throws {
        let p = try planned(cards: 0)
        let (course, read) = (p.course, p.read)
        #expect(course.study(now: PlanCourse.at(12, 8, 20)).progress(of: read) == PlanProgress(done: 0, total: 1))
        let checked = course.study(now: PlanCourse.at(12, 8, 20), log: course.checks([read.id], at: PlanCourse.at(12, 8, 19)))
        #expect(checked.progress(of: read) == PlanProgress(done: 1, total: 1) && checked.isDone(read))
    }

    @Test func checkingByHandCountsEveryCard() throws {
        let p = try planned(cards: 4, trueFalse: true)
        let (course, read) = (p.course, p.read)
        var log = flips([Flip(card: p.cards[0], at: PlanCourse.at(12, 8, 10))])
        log.checks = [(PlanCourse.at(12, 8, 11), PlanCheckEvent(itemId: read.id, done: true))]
        let study = course.study(now: PlanCourse.at(12, 8, 12), log: log)
        #expect(study.progress(of: read) == PlanProgress(done: 4, total: 4) && study.isDone(read))
        // 체크를 풀면 넘긴 만큼으로 돌아간다.
        log.checks.append((PlanCourse.at(12, 8, 13), PlanCheckEvent(itemId: read.id, done: false)))
        #expect(course.study(now: PlanCourse.at(12, 8, 14), log: log).progress(of: read) == PlanProgress(done: 1, total: 4))
    }

    @Test func aFlipBeforeTheDayBoundaryBelongsToTheDayBefore() throws {
        let p = try planned(cards: 2)
        let (course, read, cards) = (p.course, p.read, p.cards)
        // 12/8 03:59는 하루 경계(04:00) 전이라 12/7 공부일이고 기간 전이다. 04:00부터가 기간의 첫 공부일이다.
        let early = course.study(now: PlanCourse.at(12, 8, 5), log: flips([Flip(card: cards[0], at: PlanCourse.at(12, 8, 3, 59))]))
        #expect(early.progress(of: read) == PlanProgress(done: 0, total: 2))
        let onTime = course.study(now: PlanCourse.at(12, 8, 5), log: flips([Flip(card: cards[0], at: PlanCourse.at(12, 8, 4, 0))]))
        #expect(onTime.progress(of: read) == PlanProgress(done: 1, total: 2))
    }

    @Test func otherStagesAndOtherNotesKeepToTheirChecks() throws {
        let p = try planned(cards: 2)
        var course = p.course
        let (read, cards) = (p.read, p.cards)
        let paths = course.noteId("기말 10 증가 경로")
        let solve = try #require(course.exam.plan.first { $0.target == .note(read.target.id ?? UUID(), .solve) })
        let other = try #require(course.exam.plan.first { $0.target == .note(paths, .read) })
        let log = flips(cards.map { Flip(card: $0, at: PlanCourse.at(12, 8, 10)) })
        let study = course.study(now: PlanCourse.at(12, 8, 12), log: log)
        #expect(study.isDone(read) && !study.isDone(solve) && !study.isDone(other))
        #expect(study.progress(of: solve) == PlanProgress(done: 0, total: 1))
        // 다른 노트에 이은 카드나 노트에 잇지 않은 카드는 이 정독의 카드가 아니다.
        course.cards.append(StudyCard(device: course.device, at: course.made, unitId: course.hall.id, front: "단원 카드", back: "뒤"))
        #expect(course.study(now: PlanCourse.at(12, 8, 12), log: log).progress(of: read).total == 2)
    }

    @Test func progressNeverPassesTheCardsAndIgnoresFlipsBeforeThePeriod() async throws {
        let p = try planned(cards: 6)
        let (course, read, cards) = (p.course, p.read, p.cards)
        let start = PlanCourse.at(12, 8, 4)
        // 카드마다 기간 시작에서 몇 시간 떨어진 때에 넘겼는지다. 음수는 기간 전이다.
        await propertyCheck(input: Gen.int(in: -72...72).array(of: 0...18), Gen.int(in: 0...5).array(of: 18), Gen.bool) {
            hours, picks, checked in
            let list = hours.enumerated().map { i, h in
                Flip(card: cards[picks[i]], at: start.addingTimeInterval(Double(h) * 3600), known: i.isMultiple(of: 2))
            }
            var log = flips(list)
            if checked { log.checks = [(start, PlanCheckEvent(itemId: read.id, done: true))] }
            let progress = course.study(now: PlanCourse.at(12, 12), log: log).progress(of: read)
            let inPeriod = Set(list.filter { $0.at >= start }.map(\.card.id))
            #expect(progress.total == cards.count && progress.done <= progress.total)
            #expect(progress.done == (checked ? cards.count : inPeriod.count))
        }
    }

    struct TwoExams {
        var course: PlanCourse
        var hall: UUID
        var midterm: ExamPlanItem
        var final: ExamPlanItem
        var cards: [StudyCard]
    }

    // 같은 노트의 정독이 두 시험의 계획에 있다. 중간고사 기간은 10/10부터이고, 기말고사 계획은 미리 놓아 기간이 12/1부터다.
    func twoExams() throws -> TwoExams {
        var course = PlanCourse()
        let hall = course.noteId("기말 02 홀의 정리")
        let cards = (0..<6).map { course.card("카드 \($0)", note: hall) }
        var midterm = Exam(
            device: course.device, at: course.made, title: "중간고사", start: PlanCourse.at(10, 20, 9), end: PlanCourse.at(10, 20, 11))
        midterm.addedScopeUnitIds = course.exam.addedScopeUnitIds
        let study = course.study(now: PlanCourse.at(10, 10))
        func placed(_ exam: Exam, _ period: ExamPlanPeriod) throws -> Exam {
            let placed = try #require(study.place(exam, period: period, proofs: [], settings: Settings(), calendar: PlanCourse.calendar))
            var exam = exam
            exam.plan = placed.plan
            exam.planPeriod = placed.period
            exam.planBasis = placed.basis
            return exam
        }
        midterm = try placed(midterm, ExamPlanPeriod(start: PlanCourse.day(10, 10), end: PlanCourse.day(10, 19)))
        course.exam = try placed(course.exam, ExamPlanPeriod(start: PlanCourse.day(12, 1), end: PlanCourse.day(12, 13)))
        course.otherExams = [midterm]
        return TwoExams(
            course: course, hall: hall, midterm: try #require(midterm.plan.first { $0.target == .note(hall, .read) }),
            final: try #require(course.exam.plan.first { $0.target == .note(hall, .read) }), cards: cards)
    }

    @Test func theDeckFollowsTheExamWhosePeriodHasStarted() throws {
        let t = try twoExams()
        let log = flips(t.cards.prefix(3).map { Flip(card: $0, at: PlanCourse.at(10, 15)) })
        // 10/15에는 중간고사 기간만 시작했다. 칸은 중간고사의 정독과 같은 값이고 기말고사의 정독은 아직 세지 않는다.
        let october = t.course.study(now: PlanCourse.at(10, 15, 13), log: log)
        #expect(october.readExam(ofNote: t.hall)?.title == "중간고사")
        #expect(october.progress(of: t.midterm) == PlanProgress(done: 3, total: 6))
        #expect(october.noteDeck(t.hall, sections: []).progress == october.progress(of: t.midterm))
        #expect(october.progress(of: t.final) == PlanProgress(done: 0, total: 6))

        // 기말고사 기간이 시작하면 칸은 기말고사를 따른다. 중간고사의 정독은 그 시험의 기간으로 센 값 그대로다.
        let december = t.course.study(now: PlanCourse.at(12, 2), log: log)
        #expect(december.readExam(ofNote: t.hall)?.title == "기말고사")
        #expect(december.noteDeck(t.hall, sections: []).progress == december.progress(of: t.final))
        #expect(december.progress(of: t.final).done == 0 && december.progress(of: t.midterm).done == 3)
    }

    @Test func aReadingFinishedForOneExamStaysFinishedWhenALaterPeriodStarts() throws {
        let t = try twoExams()
        let log = flips(t.cards.map { Flip(card: $0, at: PlanCourse.at(10, 16)) })
        let december = t.course.study(now: PlanCourse.at(12, 2), log: log)
        #expect(december.isDone(t.midterm) && !december.isDone(t.final))
    }

    @Test func beforeAnyPeriodStartsTheDeckFollowsTheFirstToStart() throws {
        let t = try twoExams()
        // 10/9에는 어느 기간도 시작하지 않았다. 먼저 시작할 중간고사를 따르므로 그 전에 넘긴 카드는 칩에서도 칸에서도 세지 않는다.
        let study = t.course.study(now: PlanCourse.at(10, 9, 11), log: flips([Flip(card: t.cards[0], at: PlanCourse.at(10, 9, 10))]))
        #expect(study.readExam(ofNote: t.hall)?.title == "중간고사")
        #expect(study.noteDeck(t.hall, sections: []).progress == study.progress(of: t.midterm))
        #expect(study.progress(of: t.midterm).done == 0)
    }

    @Test func theDeckAlwaysCountsWhatItsExamsReadingCounts() async throws {
        let t = try twoExams()
        let first = PlanCourse.at(10, 1)
        // 카드마다 10/1에서 며칠 뒤에 넘겼는지와, 며칠 뒤에 칸을 보는지다. 12/13까지다.
        await propertyCheck(input: Gen.int(in: 0...73).array(of: 0...12), Gen.int(in: 0...5).array(of: 12), Gen.int(in: 0...73)) {
            days, picks, seen in
            let log = flips(
                days.enumerated().map { i, d in Flip(card: t.cards[picks[i]], at: first.addingTimeInterval(Double(d) * 86400)) })
            let study = t.course.study(now: first.addingTimeInterval(Double(seen) * 86400), log: log)
            let final = study.readExam(ofNote: t.hall)?.id == t.course.exam.id
            #expect(final == (study.today >= PlanCourse.day(12, 1)))
            #expect(study.noteDeck(t.hall, sections: []).progress == study.progress(of: final ? t.final : t.midterm))
        }
    }

    @Test func aNoteWithoutCardsOnlyCountsItsCheck() async throws {
        let p = try planned(cards: 0)
        let read = p.read
        var other = p.course
        let stray = other.card("다른 노트의 카드", note: other.noteId("기말 10 증가 경로"))
        await propertyCheck(input: Gen.bool, Gen.int(in: 0...48)) { checked, hour in
            var log = flips([Flip(card: stray, at: PlanCourse.at(12, 8, 4).addingTimeInterval(Double(hour) * 3600))])
            if checked { log.checks = [(PlanCourse.at(12, 8, 9), PlanCheckEvent(itemId: read.id, done: true))] }
            #expect(other.study(now: PlanCourse.at(12, 12), log: log).progress(of: read) == PlanProgress(done: checked ? 1 : 0, total: 1))
        }
    }
}
