import FolioDomain
import Foundation
import Testing

struct SemesterRunningTests {
    let device = UUID()

    func term(_ start: String?, _ end: String?) -> Semester {
        Semester(
            device: device, at: .now, year: 2027, term: .spring, start: start.flatMap { LocalDate($0) }, end: end.flatMap { LocalDate($0) })
    }

    @Test func runsFromTheFirstDayThroughTheLast() throws {
        let s = term("2027-03-02", "2027-06-18")
        #expect(!s.isRunning(on: try #require(LocalDate("2027-03-01"))))
        #expect(s.isRunning(on: try #require(LocalDate("2027-03-02"))))
        #expect(s.isRunning(on: try #require(LocalDate("2027-06-18"))))
        #expect(!s.isRunning(on: try #require(LocalDate("2027-06-19"))))
    }

    @Test func aTermWithoutBothDatesOrWithThemReversedNeverRuns() throws {
        let day = try #require(LocalDate("2027-04-01"))
        #expect(!term("2027-03-02", nil).isRunning(on: day))
        #expect(!term(nil, "2027-06-18").isRunning(on: day))
        #expect(!term("2027-06-18", "2027-03-02").isRunning(on: day))
    }

    /// What `course add`, `today` and the app take for this semester.
    @Test func theCurrentTermIsTheOneTodayFallsIn() throws {
        let spring = term("2027-03-02", "2027-06-18")
        let fall = Semester(device: device, at: .now, year: 2027, term: .fall, start: LocalDate("2027-09-01"), end: LocalDate("2027-12-18"))
        let terms = [fall, spring]
        #expect(terms.current(on: try #require(LocalDate("2027-06-18")))?.id == spring.id)
        // Between terms, the last one started; before any, the next to start.
        #expect(terms.current(on: try #require(LocalDate("2027-08-31")))?.id == spring.id)
        #expect(terms.current(on: try #require(LocalDate("2027-09-01")))?.id == fall.id)
        #expect(terms.current(on: try #require(LocalDate("2027-01-01")))?.id == spring.id)
        #expect([Semester]().current(on: try #require(LocalDate("2027-01-01"))) == nil)
    }

    @Test func aTermWithoutDatesCountsAsStartedButNotOverOneRunning() throws {
        let spring = term("2027-03-02", "2027-06-18")
        let fall = Semester(device: device, at: .now, year: 2027, term: .fall)
        let credited = Semester(device: device, at: .now, year: 2028, term: .credited)
        let terms = [spring, fall, credited]
        #expect(terms.current(on: try #require(LocalDate("2027-04-01")))?.id == spring.id)
        #expect(terms.current(on: try #require(LocalDate("2027-07-01")))?.id == fall.id)
        #expect([credited].current(on: try #require(LocalDate("2027-07-01"))) == nil)
    }
}
