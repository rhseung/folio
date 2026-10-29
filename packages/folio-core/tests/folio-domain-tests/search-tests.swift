import FolioDomain
import Foundation
import Testing

struct SearchTests {
    let course = UUID()

    func item(_ kind: SearchKind, _ title: String, _ body: String = "") -> SearchItem {
        SearchItem(kind: kind, courseId: course, id: UUID(), title: title, body: body)
    }

    @Test func ranksTitleMatchesAboveBodyMatches() {
        let index = SearchIndex([
            item(.note, "2주차-1", "오늘은 matching 의 정의를 배웠다"),
            item(.material, "05_Matchings.pdf", "Lectures/05_Matchings.pdf"),
            item(.unit, "Matchings and Covers"),
            item(.unit, "matching"),
            item(.assignment, "HW3"),
        ])
        let titles = index.search("Matching").map(\.item.title)
        #expect(titles == ["matching", "Matchings and Covers", "05_Matchings.pdf", "2주차-1"])
    }

    @Test func everyWordMustMatchSomewhere() {
        let index = SearchIndex([
            item(.note, "Hall's theorem", "proof by induction on matchings"),
            item(.note, "Hall's theorem notes", "nothing here"),
        ])
        let hits = index.search("hall induction")
        #expect(hits.map(\.item.title) == ["Hall's theorem"])
        #expect(hits[0].snippet?.contains("induction") == true)
        #expect(index.search("   ").isEmpty)
    }

    @Test func decomposedFileNamesMatchTypedHangul() {
        let nfd = "강의계획서.pdf".decomposedStringWithCanonicalMapping
        let index = SearchIndex([item(.material, nfd)])
        #expect(index.search("강의").count == 1)
    }

    @Test func snippetShowsTheMatchOnOneLine() throws {
        let body = String(repeating: "앞 문장. ", count: 20) + "\n핵심은 증가 경로다.\n" + String(repeating: "뒤 문장. ", count: 20)
        let hit = try #require(SearchIndex([item(.note, "정리", body)]).search("증가 경로").first)
        let snippet = try #require(hit.snippet)
        #expect(snippet.hasPrefix("…") && snippet.hasSuffix("…") && !snippet.contains("\n") && snippet.contains("증가"))
    }

    @Test func itemsCoverEveryKindAndSkipIgnoredFiles() {
        let device = UUID(), now = Date(timeIntervalSince1970: 0)
        var file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        file.materials = [
            Material(device: device, at: now, path: "Lectures/05_Matchings.pdf", status: .classified),
            Material(device: device, at: now, path: "junk.txt", status: .ignored),
        ]
        file.assignments = [Assignment(device: device, at: now, title: "HW3")]
        var session = Session(device: device, at: now, week: 2, index: 1, date: now)
        session.topic = "Matchings"
        file.sessions = [session]
        file.units = [Unit(device: device, at: now, title: "Covers", order: 1)]
        let card = QuizCard(device: device, at: now, unitId: file.units[0].id, type: .free, category: .definition, prompt: "덮개의 정의", answer: "모든 꼭짓점을 덮는 변 집합")
        let items = SearchIndex.items(for: file, notes: [(UUID(), "2주차-1", "본문")], cards: [card])
        #expect(items.map(\.kind) == [.note, .material, .assignment, .session, .unit, .quiz])
        #expect(items.map(\.title) == ["2주차-1", "05_Matchings.pdf", "HW3", "2주차-1 · Matchings", "Covers", "덮개의 정의"])
        #expect(items.last?.body == "모든 꼭짓점을 덮는 변 집합")
    }
}
