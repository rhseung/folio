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
        file.exams = [Exam(device: device, at: now, title: "중간고사")]
        let session = Session(device: device, at: now, week: 2, date: now)
        file.sessions = [session]
        var covers = Unit(device: device, at: now, title: "Covers", order: 1)
        covers.sessionIds = [session.id]
        file.units = [covers]
        let card = QuizCard(device: device, at: now, unitId: file.units[0].id, type: .free, category: .definition, prompt: "덮개의 정의", answer: "모든 꼭짓점을 덮는 변 집합")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let items = SearchIndex.items(for: file, notes: [(UUID(), "09-08(화) 매칭", "본문")], cards: [card], calendar: calendar)
        #expect(items.map(\.kind) == [.note, .material, .assignment, .exam, .session, .unit, .quiz])
        // A class goes by its day and units, and its reference is in the body so `11-03` finds it.
        #expect(items.map(\.title) == ["09-08(화) 매칭", "05_Matchings.pdf", "HW3", "중간고사", file.title(of: session, calendar: calendar), "Covers", "덮개의 정의"])
        #expect(items[4].title.hasSuffix(": Covers") && items[4].body == file.reference(of: session, calendar: calendar))
        #expect(items.last?.body == "모든 꼭짓점을 덮는 변 집합")
    }
}
