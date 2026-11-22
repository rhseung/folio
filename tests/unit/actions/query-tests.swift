import FolioActions
import FolioCore
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct QueryTests {
    static let graphTheory = ActionTests.graphTheory
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
    }

    func read<Q: Query>(_ query: Q) throws -> Q.Result {
        try query.read(ReadContext(ActionContext(gist: gist, device: UUID(), now: now)))
    }

    @Test func everyQueryIsListedOnce() {
        let commands = Queries.all.map { $0.spec.command }
        #expect(Set(commands).count == commands.count)
        #expect(Set(commands).isDisjoint(with: Actions.all.map { $0.command }))
    }

    @Test func readsReturnTheItem() throws {
        let ctx = ActionContext(gist: gist, device: UUID(), now: now)
        try ExamAdd(course: Self.graphTheory, title: "기말고사").run(ctx)
        try UnitAdd(course: Self.graphTheory, title: "매칭").run(ctx)
        let file = try ActionContext(gist: gist, device: UUID()).file(Self.graphTheory)
        #expect(try read(CourseShow(course: Self.graphTheory)).id == Self.graphTheory)
        let exam = try #require(file.exams.first)
        #expect(try read(ExamShow(course: Self.graphTheory, exam: exam.id)).item == exam)
        let unit = try #require(file.units.first)
        #expect(try read(UnitShow(course: Self.graphTheory, unit: unit.id)).item == unit)
    }

    @Test func noSemesterMeansTheCurrentOne() throws {
        let today = LocalDate(now, in: .current)
        let expected = try ActionContext(gist: gist, device: UUID()).transcript().semesters.current(on: today)
        #expect(try read(SemesterShow(semester: nil)).id == expected?.id)
    }

    @Test func aMissingItemIsNotFound() throws {
        #expect {
            try read(ExamShow(course: Self.graphTheory, exam: UUID()))
        } throws: { error in
            if case .notFound = error as? ActionError { true } else { false }
        }
    }
}
