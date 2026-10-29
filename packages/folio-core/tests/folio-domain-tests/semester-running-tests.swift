import FolioDomain
import Foundation
import Testing

struct SemesterRunningTests {
    let device = UUID()

    func term(_ start: String?, _ end: String?) -> Semester {
        Semester(device: device, at: .now, year: 2027, term: .spring, start: start.flatMap { LocalDate($0) }, end: end.flatMap { LocalDate($0) })
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
}
