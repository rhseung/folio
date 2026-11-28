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
