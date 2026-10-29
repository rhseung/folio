import CoreText
import FolioActions
import FolioDomain
import FolioFixtures
@testable import FolioIndex
import FolioStorage
import Foundation
import Testing

struct SearchStoreTests {
    let graphTheory = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!
    let robotics = UUID(uuidString: "C0000000-0000-4000-8000-000000000003")!

    func fixture() throws -> GISTStore {
        GISTStore(url: try Fixture.standard.copyToTemp())
    }

    /// A one-page PDF whose text layer says `text`; the fixture PDFs are placeholders with none.
    func writePDF(_ text: String, to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 400, height: 200)
        let ctx = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, 14, nil)]))
        ctx.textPosition = CGPoint(x: 20, y: 100)
        CTLineDraw(line, ctx)
        ctx.endPDFPage()
        ctx.closePDF()
    }

    @Test func findsNotesSessionsAndShortKoreanWords() throws {
        let gist = try fixture()
        let index = try SearchStore(url: nil)
        #expect(try index.refresh(gist) > 0)
        let hits = try index.search("non-adjacent")
        #expect(hits.first?.item.kind == .note)
        #expect(hits.first?.snippet?.contains("non-adjacent") == true)
        // Two-letter Hangul is below the trigram length, so this goes through the scan path.
        #expect(try index.search("주차").contains { $0.item.title == "2주차-1" })
        #expect(try index.search("no such words here").isEmpty)
    }

    @Test func readsPDFText() throws {
        let gist = try fixture()
        let root = gist.url.appending(path: "2026-3/EC4207 그래프 이론")
        try writePDF("Hall marriage theorem", to: root.appending(path: "Lectures/05_Matchings.pdf"))
        try MaterialTrack(course: graphTheory).run(ActionContext(gist: gist, device: UUID(), now: .now))
        let index = try SearchStore(url: nil)
        try index.refresh(gist)
        let hit = try #require(try index.search("marriage").first)
        #expect(hit.item.kind == .material)
        #expect(hit.item.title == "05_Matchings.pdf")
        #expect(hit.snippet?.contains("marriage") == true)
    }

    @Test func readsOnlyWhatChanged() throws {
        let gist = try fixture()
        let index = try SearchStore(url: gist.url.deletingLastPathComponent().appending(path: "cache/search.sqlite"))
        try index.refresh(gist)
        #expect(try index.refresh(gist) == 0)

        let note = gist.url.appending(path: "2026-3/EC4207 그래프 이론/Notes/2주차-1.md")
        try (String(contentsOf: note, encoding: .utf8) + "\nKőnig theorem\n").write(to: note, atomically: true, encoding: .utf8)
        #expect(try index.refresh(gist) == 1)
        #expect(try index.search("theorem").map(\.item.kind) == [.note])

        // A reopened index keeps what it read.
        let again = try SearchStore(url: gist.url.deletingLastPathComponent().appending(path: "cache/search.sqlite"))
        #expect(try again.refresh(gist) == 0)
        #expect(try again.search("theorem").count == 1)
    }

    @Test func findsQuizCardsAndNoticesNewOnes() throws {
        let gist = try fixture()
        let ctx = ActionContext(gist: gist, device: UUID(), now: .now)
        let unit = UUID()
        try UnitAdd(id: unit, course: graphTheory, title: "매칭").run(ctx)
        let index = try SearchStore(url: nil)
        try index.refresh(gist)
        #expect(try index.search("augmenting", kinds: [.quiz]).isEmpty)

        // Cards live in their own file, so adding one leaves course.json alone and still has to count as a change.
        let card = QuizCard(device: ctx.device, at: ctx.now, unitId: unit, type: .free, category: .theorem, prompt: "Berge의 정리", answer: "augmenting path가 없으면 최대 매칭")
        try QuizCardSave(course: graphTheory, cards: [card], movedFrom: nil).run(ctx)
        #expect(try index.refresh(gist) == 1)
        let hit = try #require(try index.search("augmenting").first)
        #expect(hit.item.kind == .quiz && hit.item.id == card.id && hit.item.title == "Berge의 정리")
    }

    @Test func filtersAndForgetsRemovedCourses() throws {
        let gist = try fixture()
        let index = try SearchStore(url: nil)
        try index.refresh(gist)
        #expect(try index.search("1주차", courses: [robotics]).allSatisfy { $0.item.courseId == robotics })
        #expect(try index.search("1주차", kinds: [.unit]).allSatisfy { $0.item.kind == .unit })
        #expect(try index.search("1주차", courses: [robotics]).isEmpty == false)

        try FileManager.default.removeItem(at: gist.url.appending(path: "2026-3/EC4321 로봇공학"))
        try index.refresh(gist)
        #expect(try index.search("1주차", courses: [robotics]).isEmpty)
    }
}

struct SearchProgressTests {
    @Test func reportsEachCourseThenDone() throws {
        let gist = try SearchStoreTests().fixture()
        let index = try SearchStore(url: nil)
        let seen = Seen()
        let read = try index.refresh(gist) { done, total in seen.append((done, total)) }
        #expect(read > 0)
        #expect(seen.steps.map(\.0) == Array(0...read))
        #expect(seen.steps.allSatisfy { $0.1 == read })
        let again = Seen()
        try index.refresh(gist) { done, total in again.append((done, total)) }
        #expect(again.steps.isEmpty)
    }
}

private final class Seen: @unchecked Sendable {
    var steps: [(Int, Int)] = []
    func append(_ s: (Int, Int)) { steps.append(s) }
}
