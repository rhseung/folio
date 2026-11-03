import Foundation
import Testing
@testable import FolioDomain

struct TranscriptionHintsTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)

    func course(_ paths: [String]) -> CourseFile {
        var file = CourseFile(course: Course(device: device, at: now, title: "컴파일러"))
        file.materials = paths.map { Material(device: device, at: now, path: $0, role: .lecture, status: .classified) }
        file.sessions = [Session(device: device, at: now, week: 5, index: 1, date: now)]
        return file
    }

    @Test func aLinkedLectureIsReadWithinItsPages() {
        var file = course(["Lectures/05_Parsing.pdf", "Lectures/06_LR.pdf"])
        file.sessions[0].materials = [SessionMaterial(materialId: file.materials[1].id, firstPage: 3, lastPage: 9)]
        #expect(file.lecturePages(for: file.sessions[0]) == [LecturePages(path: "Lectures/06_LR.pdf", first: 3, last: 9)])
    }

    @Test func anUnlinkedClassReadsItsWeeksLectures() {
        let file = course(["Lectures/05-2_LR.pdf", "Lectures/05-1_Parsing.pdf", "Lectures/15_Review.pdf", "Lectures/05_notes.txt", "Syllabus/05_Plan.pdf"])
        #expect(file.lecturePages(for: file.sessions[0]).map(\.path) == ["Lectures/05-1_Parsing.pdf", "Lectures/05-2_LR.pdf"])
    }

    @Test func aClassTaggedWithAUnitReadsTheUnitsSlides() {
        var file = course(["Lectures/03 Syntax-analysis.pdf", "Lectures/04 Semantic-analysis.pdf"])
        let unit = Unit(device: device, at: now, title: "LR Parsing", order: 0)
        file.units = [unit]
        file.sessions[0].unitIds = [unit.id]
        file.materials[0].unitIds = [unit.id]
        #expect(file.lecturePages(for: file.sessions[0]).map(\.path) == ["Lectures/03 Syntax-analysis.pdf"])
    }

    @Test func topicsAndUnitsComeBeforeTheSlides() {
        var file = course([])
        let parent = Unit(device: device, at: now, title: "Syntax Analysis", order: 0)
        var child = Unit(device: device, at: now, title: "LR Parsing", order: 1, parentId: parent.id)
        child.sessionIds = [file.sessions[0].id]
        file.units = [parent, child]
        file.sessions[0].topic = "SLR과 LALR"
        let hints = file.transcriptionHints(for: file.sessions[0], slides: "lookahead, lookahead, syntax analysis, syntax analysis, LALR")
        #expect(hints.title == "컴파일러")
        // A slide term the units already said, in another case, is not said twice.
        #expect(hints.terms == ["SLR과 LALR", "LR Parsing", "Syntax Analysis", "lookahead", "syntax", "analysis", "LALR"])
    }

    @Test func termsAreTheEnglishOnTheSlides() {
        let text = """
        LR 파싱과 Shift-reduce conflict
        shift-reduce conflict는 LALR 파서에서 생긴다. The parser uses a lookahead.
        Left factoring 을 하면 top-down parser가 쓸 수 있다. left factoring 예시
        """
        let terms = LectureTerms.terms(in: text)
        #expect(terms.prefix(3).contains("Shift-reduce conflict") || terms.contains("shift-reduce conflict"))
        #expect(terms.contains("LR"))
        #expect(terms.contains("LALR"))
        #expect(terms.contains { $0.lowercased() == "left factoring" })
        // A pair seen once is not a term, and plain English words are not either.
        #expect(!terms.contains("top-down parser"))
        #expect(!terms.contains("The"))
        // What the slides repeat comes first; a word said once only fills what is left.
        #expect(terms.firstIndex { $0.lowercased() == "left factoring" }! < terms.firstIndex(of: "uses")!)
    }

    @Test func tiesAreOrderedTheSameEveryRun() {
        let terms = LectureTerms.terms(in: "shift-reduce conflict, shift-reduce conflict, beta alpha, gamma")
        #expect(terms == ["shift-reduce conflict", "shift-reduce", "conflict", "beta", "alpha", "gamma"])
    }

    @Test func theMostUsedSpellingWins() {
        let terms = LectureTerms.terms(in: "lookahead Lookahead lookahead")
        #expect(terms == ["lookahead"])
    }

    @Test func termsAreCapped() {
        let text = (1...100).map { "Term\($0)" }.joined(separator: ", ")
        #expect(LectureTerms.terms(in: text, limit: 10).count == 10)
    }

    @Test func thePromptHasNoKoreanFraming() {
        let hints = TranscriptionHints(title: "Compiler", terms: ["LALR", "left factoring", "FIRST set"])
        #expect(hints.prompt() == "Compiler. LALR, left factoring, FIRST set.")
        #expect(hints.prompt(terms: 1) == "Compiler. LALR.")
        #expect(TranscriptionHints(title: "Compiler", terms: []).prompt() == "Compiler.")
    }
}
