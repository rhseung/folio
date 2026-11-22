import FolioCore
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct StudyLogTests {
    let device = UUID()
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }()

    func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)) ?? .distantPast
    }

    @Test func solvesAndFlipsRoundTripThroughTheLog() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first { $0.url.lastPathComponent == "EC4207 그래프 이론" })

        var doc = try store.load()
        let unit = FolioDomain.Unit(device: device, at: at(1, 9), title: "Matchings", order: 1)
        let set = ProblemSet(
            device: device, at: at(1, 9), title: "HW3", source: .assignment, problems: [Problem(number: "1", unitIds: [unit.id])])
        doc.model.units = [unit]
        doc.model.problemSets = [set]
        try store.save(doc)

        var cards = try store.loadCards(unit: unit.id)
        let card = StudyCard(device: device, at: at(1, 9), unitId: unit.id, front: "매칭", back: "끝점을 공유하지 않는 변 집합")
        cards.model.cards = [card]
        try store.save(cards)

        // 3일 02:00은 04:00 경계 전이라 2일 공부일이다. 3일 09:00에 맞히면 다른 날이라 오답에서 빠진다.
        let wrong = ProblemSolveEvent(setId: set.id, problemId: set.problems[0].id, verdict: .wrong, basis: .solution)
        try store.log.append(wrong, device: device, at: at(3, 2))
        try store.log.append(
            ProblemSolveEvent(setId: set.id, problemId: set.problems[0].id, verdict: .correct, basis: .solution), device: device,
            at: at(3, 9))
        try store.log.append(CardFlipEvent(cardId: card.id, known: false), device: device, at: at(3, 9))

        let log = try store.log.readAll().studyLog
        #expect(log.solves.map(\.event).first == wrong && log.flips.count == 1)
        let study = CourseStudy(
            file: try store.load().model, cards: try store.loadCards(unit: unit.id).model.cards, log: log, settings: Settings(),
            calendar: calendar, now: at(3, 12))
        #expect(study.problems[set.problems[0].id]?.status == .resolved(on: ymd("2026-10-03")))
        #expect(study.cards[card.id]?.status == .open(since: ymd("2026-10-03")))
    }
}

private func ymd(_ text: String) -> LocalDate {
    guard let day = LocalDate(text) else { preconditionFailure(text) }
    return day
}
