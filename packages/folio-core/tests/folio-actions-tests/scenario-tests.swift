import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct ScenarioTests {
    func summary(_ scenario: Scenario) throws -> TodaySummary {
        let gist = GISTStore(url: try scenario.copyToTemp())
        let ctx = ActionContext(gist: gist, device: UUID(), now: scenario.now, calendar: Scenario.calendar)
        let fall = try ctx.transcript().semesters.first { $0.term == .fall }
        let courses = try gist.courseStores().map { try $0.load().model }.filter { $0.course.semesterId == fall?.id }
        return TodaySummary.build(courses: courses, now: scenario.now, settings: try ctx.settings(), calendar: Scenario.calendar)
    }

    @Test func aBusyDayIsFull() throws {
        let s = try summary(.busyDay)
        #expect(s.classesToday.count == 6)
        #expect(s.deadlines.count >= 7)
        #expect((2...4).contains(s.exams.count))
        #expect(!s.missingReviewNotes.isEmpty)
    }

    @Test func manyExamsAreMoreThanFitInARow() throws {
        #expect(try summary(.manyExams).exams.count == 6)
    }

    @Test func aQuietDayHasNoClassesAndTheEmptyOneNothing() throws {
        let quiet = try summary(.quietDay)
        #expect(quiet.classesToday.isEmpty)
        #expect((1...3).contains(quiet.deadlines.count))
        let empty = try summary(.empty)
        #expect(empty.classesToday.isEmpty && empty.deadlines.isEmpty && empty.exams.isEmpty)
    }
}
