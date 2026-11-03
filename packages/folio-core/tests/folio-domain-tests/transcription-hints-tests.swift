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
        let slides = file.lectureSlides(for: file.sessions[0])
        #expect(slides.source == .session)
        #expect(slides.pages == [LecturePages(path: "Lectures/06_LR.pdf", first: 3, last: 9, materialId: file.materials[1].id)])
    }

    @Test func anUnlinkedClassReadsItsWeeksLectures() {
        let file = course(["Lectures/05-2_LR.pdf", "Lectures/05-1_Parsing.pdf", "Lectures/15_Review.pdf", "Lectures/05_notes.txt", "Syllabus/05_Plan.pdf"])
        let slides = file.lectureSlides(for: file.sessions[0])
        #expect(slides.source == .week)
        #expect(slides.pages.map(\.path) == ["Lectures/05-1_Parsing.pdf", "Lectures/05-2_LR.pdf"])
    }

    @Test func aClassTaggedWithAUnitReadsTheUnitsSlides() {
        var file = course(["Lectures/03 Syntax-analysis.pdf", "Lectures/04 Semantic-analysis.pdf"])
        let unit = Unit(device: device, at: now, title: "LR Parsing", order: 0)
        file.units = [unit]
        file.sessions[0].unitIds = [unit.id]
        file.materials[0].unitIds = [unit.id]
        let slides = file.lectureSlides(for: file.sessions[0])
        #expect(slides.source == .tagged)
        #expect(slides.pages.map(\.path) == ["Lectures/03 Syntax-analysis.pdf"])
    }

    @Test func topicsAndUnitsComeBeforeTheSlides() {
        var file = course([])
        let parent = Unit(device: device, at: now, title: "Syntax Analysis", order: 0)
        var child = Unit(device: device, at: now, title: "LR Parsing", order: 1, parentId: parent.id)
        child.sessionIds = [file.sessions[0].id]
        file.units = [parent, child]
        file.sessions[0].topic = "SLR과 LALR"
        let hints = file.transcriptionContext(for: file.sessions[0]).reading("lookahead, lookahead, syntax analysis, syntax analysis, LALR").hints(course: file.course.title)
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

    func recording(_ file: CourseFile, _ visits: [PageVisit], duration: TimeInterval = 600) -> Recording {
        Recording(device: device, at: now, sessionId: file.sessions[0].id, file: "Recordings/5주차-1.m4a", duration: duration, pages: visits)
    }

    @Test func pagesLeftOnScreenWinOverLinks() {
        var file = course(["Lectures/05_Parsing.pdf", "Lectures/06_LR.pdf"])
        file.sessions[0].materials = [SessionMaterial(materialId: file.materials[0].id)]
        let lr = file.materials[1].id
        let r = recording(file, [PageVisit(at: 0, materialId: lr, page: 4), PageVisit(at: 60, materialId: lr, page: 7)])
        let slides = file.lectureSlides(for: file.sessions[0], recording: r)
        #expect(slides.source == .recording)
        #expect(slides.pages == [LecturePages(path: "Lectures/06_LR.pdf", first: 4, last: 7, materialId: lr)])
        // Without the recording the session's own link is read, whole.
        #expect(file.lectureSlides(for: file.sessions[0]).source == .session)
    }

    @Test func aClassWithNothingLinkedHasNoSource() {
        let file = course(["Syllabus/Plan.pdf"])
        let context = file.transcriptionContext(for: file.sessions[0])
        #expect(context.source == nil && context.slides.isEmpty && context.topics.isEmpty)
    }

    @Test func aContextDiffersWhenTheSlidesOrUnitsMoveOn() {
        var file = course(["Lectures/05_Parsing.pdf", "Lectures/06_LR.pdf"])
        let used = file.transcriptionContext(for: file.sessions[0]).reading("lookahead lookahead")
        #expect(used.source == .week && used.terms == ["lookahead"])
        // Terms are not compared: knowing them means reading the slides again.
        #expect(!used.differs(from: file.transcriptionContext(for: file.sessions[0])))
        file.sessions[0].materials = [SessionMaterial(materialId: file.materials[1].id, firstPage: 2, lastPage: 5)]
        #expect(used.differs(from: file.transcriptionContext(for: file.sessions[0])))
        let linked = file.transcriptionContext(for: file.sessions[0])
        file.sessions[0].materials[0].lastPage = 6
        #expect(linked.differs(from: file.transcriptionContext(for: file.sessions[0])))
        file.sessions[0].materials[0].lastPage = 5
        file.sessions[0].topic = "LR"
        #expect(linked.differs(from: file.transcriptionContext(for: file.sessions[0])))
    }

    @Test func aRenamedFileIsTheSameSlides() {
        var file = course(["Lectures/05_Parsing.pdf"])
        file.sessions[0].materials = [SessionMaterial(materialId: file.materials[0].id)]
        let used = file.transcriptionContext(for: file.sessions[0])
        file.materials[0].path = "Lectures/05_Syntax.pdf"
        #expect(!used.differs(from: file.transcriptionContext(for: file.sessions[0])))
    }

    @Test func aContextRoundTripsAndToleratesAnUnknownSource() throws {
        let file = course(["Lectures/05_Parsing.pdf"])
        let context = file.transcriptionContext(for: file.sessions[0]).reading("LALR LALR")
        let transcript = LectureTranscript(locale: "ko-KR", lines: [.init(start: 0, end: 1, text: "파싱")], context: context)
        let data = try JSONEncoder().encode(transcript)
        #expect(try JSONDecoder().decode(LectureTranscript.self, from: data) == transcript)
        let newer = Data(#"{"schemaVersion":1,"locale":"ko-KR","lines":[],"context":{"source":"camera","slides":[],"topics":["LR"],"terms":[]}}"#.utf8)
        let read = try JSONDecoder().decode(LectureTranscript.self, from: newer)
        #expect(read.context?.source == nil && read.context?.topics == ["LR"])
        let old = Data(#"{"schemaVersion":1,"locale":"ko-KR","lines":[{"start":0,"end":1,"text":"a"}]}"#.utf8)
        #expect(try JSONDecoder().decode(LectureTranscript.self, from: old).context == nil)
    }
}
