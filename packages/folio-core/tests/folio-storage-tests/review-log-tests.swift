import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct ReviewLogTests {
    let device = UUID()
    let settings = Settings()
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func state(_ store: CourseStore, now: Date) throws -> ReviewState {
        let file = try store.load().model
        let reviews = try store.log.readAll().compactMap { e in try e.decode(ReviewEvent.self).map { (e.at, $0) } }
        let input = try #require(UnitReviewInput.all(for: file, reviews: reviews, settings: settings, calendar: calendar, now: now).first)
        return ReviewScheduler.state(of: input, settings: settings.review, today: settings.studyDay(of: now, calendar: calendar))
    }

    @Test func reviewEventRoundTripsAndAdvancesTheUnit() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first { $0.url.lastPathComponent == "EC4207 그래프 이론" })

        var doc = try store.load()
        let unit = FolioDomain.Unit(device: device, at: at(1, 9), title: "Matchings", order: 1)
        var session = Session(device: device, at: at(1, 9), week: 2, index: 1, date: at(1, 10))
        session.reviewNoteId = UUID()
        doc.model.units = [unit]
        doc.model.sessions = [session]
        doc.model.toggle(session: session.id, unit: unit.id)
        try store.save(doc)

        let before = try state(store, now: at(2, 12))
        #expect(before.step == 0 && before.due == LocalDate("2026-10-02"))

        // Finished at 02:00 on the 3rd: before the 04:00 boundary, so it counts for the 2nd.
        let event = ReviewEvent(unitId: unit.id, result: .good, seconds: 600)
        try store.log.append(event, device: device, at: at(3, 2))
        try store.log.append(StudySessionEvent(courseId: doc.model.course.id, start: at(3, 1), end: at(3, 2), screen: "review"), device: device, at: at(3, 2))

        let logged = try store.log.readAll()
        #expect(try logged.compactMap { try $0.decode(ReviewEvent.self) } == [event])
        #expect(try logged.compactMap { try $0.decode(StudySessionEvent.self) }.map(\.screen) == ["review"])

        let after = try state(store, now: at(3, 12))
        #expect(after.step == 1 && after.due == LocalDate("2026-10-05"))
    }
}
