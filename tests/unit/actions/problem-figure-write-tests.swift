import FolioActions
import FolioCore
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct ProblemFigureWriteTests {
    static let course = ActionTests.graphTheory
    static let svg =
        #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20"><line class="s-ink" x1="2" y1="10" x2="38" y2="10"/></svg>"#
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore
    let set = UUID()
    let stem = UUID()

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
        try run(
            ProblemSetAdd(
                id: set, course: Self.course, title: "Midterm",
                problems: [Problem(number: "1", text: "Is it planar?"), Problem(number: "2a", parent: "2", text: "Decide.")],
                groups: [ProblemGroup(id: stem, number: "2", text: "Let $G$ be the graph below.")]))
    }

    @discardableResult
    func run(_ action: some Action, dryRun: Bool = false) throws -> ActionContext {
        let ctx = ActionContext(gist: gist, device: device, now: now, dryRun: dryRun)
        try action.run(ctx)
        return ctx
    }

    var store: CourseStore { get throws { try ActionContext(gist: gist, device: device).store(Self.course) } }
    func problem(_ number: String) throws -> UUID {
        try #require(
            try ActionContext(gist: gist, device: device).file(Self.course).problemSets.first?.problems.first { $0.number == number }?.id)
    }

    // 그림은 쓸 때 노트 그림처럼 마무리한다. 문제와 지문 모두 번호로 가리킨다.
    @Test func figuresAreFinishedAndKeptPerProblemOrStem() throws {
        let ctx = try run(ProblemFigureWrite(course: Self.course, set: set, number: "2", figure: Self.svg))
        #expect(ctx.changes.map(\.kind) == [.added])
        try run(ProblemFigureWrite(course: Self.course, set: set, number: "2a", solutionFigure: Self.svg))
        let art = try store.problemArt()
        let finished = try NoteFigureFinish.finish(Self.svg).svg
        #expect(art[stem]?.model.figure == finished && art[stem]?.model.solutionFigure == nil)
        #expect(art[try problem("2a")]?.model.solutionFigure == finished)

        // 다시 쓰면 바꾼다. 둘 다 빼면 그릴 것이 없다고 남겨 문제집이 다시 묻지 않는다.
        let again = try run(ProblemFigureWrite(course: Self.course, set: set, number: "2"))
        #expect(again.changes.map(\.kind) == [.changed])
        #expect(try store.problemArt()[stem].map { $0.model.figure == nil && $0.model.solutionFigure == nil } == true)
    }

    @Test func aFigureThatFailsTheCheckOrAnUnknownNumberIsRefused() throws {
        let script = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><script>alert(1)</script></svg>"#
        #expect(throws: ActionError.self) { try run(ProblemFigureWrite(course: Self.course, set: set, number: "1", figure: script)) }
        #expect(throws: ActionError.self) { try run(ProblemFigureWrite(course: Self.course, set: set, number: "9", figure: Self.svg)) }
        #expect(try store.problemArt().isEmpty)
    }

    // 그린 PDF를 넘긴 항목만 다시 그린 그림으로 넣고, 그 PDF를 빌드 폴더에 둔다.
    @Test func theCollectionUsesOnlyTheRenderedArt() throws {
        let file = try ActionContext(gist: gist, device: device).file(Self.course)
        let one = try problem("1")
        let files = ProblemCollectionFiles(
            store: try store, file: file, semester: nil, author: "", sets: [set],
            art: [one: .init(figure: Data("%PDF art".utf8)), stem: .init()])
        #expect(files.collection.art.keys.sorted() == [one] && files.collection.art[one]?.figure == "art-\(one.uuidString).pdf")
        #expect(files.collection.problemsTeX.contains("\\artfigure{art-\(one.uuidString).pdf}"))
    }
}
