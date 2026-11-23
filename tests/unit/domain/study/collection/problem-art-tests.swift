import FolioCore
import FolioDomain
import Foundation
import Testing

struct ProblemArtTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let figures = [ProblemRegion(page: 2, x: 0.2, y: 0.3, width: 0.5, height: 0.25)].compactMap { $0 }

    // 문제지: 1(그림, 풀이 있음), 지문 2(그림) 아래 2a(풀이 없음)와 2b(풀이 있음), 3(그림 없음, 풀이 없음).
    var midterm: ProblemSet {
        ProblemSet(
            device: device, at: now, title: "Midterm",
            problems: [
                Problem(number: "1", text: "Is $K_{3,3}$ planar?", format: .trueFalse, answer: "거짓", solution: "No.", figures: figures),
                Problem(number: "2a", parent: "2", text: "State Hall's theorem.", format: .written),
                Problem(number: "2b", parent: "2", text: "Decide.", format: .written, solution: "Yes."),
                Problem(number: "3", text: "Find $\\chi(P)$.", format: .short, answer: "3"),
            ], groups: [ProblemGroup(number: "2", text: "Let $G$ be the graph below.", figures: figures)])
    }

    func jobs(_ s: ProblemSet, picked: [String], sheet: Bool = true, drawn: Set<UUID> = []) -> [String] {
        let ids = Set(s.problems.filter { picked.contains($0.number) }.map(\.id))
        return ProblemArt.jobs(sets: [s], picked: ids, sheets: sheet ? [s.id] : [], drawn: drawn).map { job in
            (job.stem != nil ? "stem " : "") + job.number + (job.draws ? " draw" : "") + (job.writesSolution ? " solve" : "")
        }
    }

    // 지문을 먼저 그린다. 문제의 풀이용 그림이 지문의 그림 위에 그려야 하기 때문이다. 그림이 지문에만 있는 소문제도 풀이용
    // 그림을 맡긴다.
    @Test func stemsComeFirstAndProblemsUnderAFiguredStemAreDrawn() {
        #expect(jobs(midterm, picked: ["1", "2a", "2b", "3"]) == ["stem 2 draw", "1 draw", "2a draw solve", "2b draw", "3 solve"])
        // 고르지 않은 문제의 지문은 맡기지 않는다.
        #expect(jobs(midterm, picked: ["1"]) == ["1 draw"])
    }

    // 자른 그림을 보고 그리므로 문제지 PDF가 없으면 그리지 않고, 풀이가 없는 문제의 풀이만 맡긴다.
    @Test func withoutASheetOnlyMissingSolutionsAreWritten() {
        #expect(jobs(midterm, picked: ["1", "2a", "2b", "3"], sheet: false) == ["2a solve", "3 solve"])
    }

    // 이미 그린 항목은 다시 그리지 않는다. 그릴 것이 없다고 답한 항목도 기록이 있어 다시 묻지 않는다.
    @Test func drawnItemsAreNotDrawnAgain() {
        let m = midterm
        let drawn = Set([m.groups[0].id, m.problems[0].id, m.problems[1].id])
        #expect(jobs(m, picked: ["1", "2a", "2b"], drawn: drawn) == ["2a solve", "2b draw"])
    }

    @Test func thePrintPageTakesItsSizeFromTheViewBox() throws {
        let page = try #require(ProblemArt.printPage(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 260 180.5"><g/></svg>"#))
        #expect(page.width == 260 && page.height == 180.5)
        #expect(page.html.contains("width:260.0px;height:180.5px") && page.html.contains("color-scheme:light"))
        #expect(ProblemArt.printPage(#"<svg width="10" height="10"/>"#) == nil)
        // 안쪽 요소의 viewBox(symbol, marker)는 그림의 크기가 아니다.
        #expect(ProblemArt.printPage(#"<svg><symbol viewBox="0 0 5 5"/></svg>"#) == nil)
    }

    // 다시 그린 그림이 있으면 자른 그림 대신 넣고, 풀이용 그림은 풀이집의 풀이 앞에 넣는다.
    @Test func redrawnFiguresReplaceTheCropsAndTheAnswerFigureLeadsTheSolution() throws {
        let m = midterm
        let picked = Set(m.problems.map(\.id))
        let sections = ProblemCollection.sections(sets: [m], picked: picked, sheets: [m.id: "sheet-1.pdf"])
        let art: [UUID: ProblemCollection.Art] = [
            m.groups[0].id: .init(figure: "art-stem.pdf"), m.problems[2].id: .init(solution: "art-2b-solution.pdf"),
        ]
        let collection = ProblemCollection(course: "C", sections: sections, art: art)
        let problems = collection.problemsTeX, solutions = collection.solutionsTeX
        #expect(problems.contains("\\artfigure{art-stem.pdf}"))
        // 1은 다시 그리지 않았으므로 자른 그림이 남는다. 지문의 그림은 다시 그린 것 하나뿐이다.
        #expect(problems.components(separatedBy: "\\sheetfigure{sheet-1.pdf}").count - 1 == 1)
        #expect(!problems.contains("art-2b-solution.pdf"))
        let solved = try #require(solutions.range(of: "\\artfigure{art-2b-solution.pdf}"))
        let text = try #require(solutions.range(of: "Yes."))
        #expect(solved.lowerBound < text.lowerBound)
    }
}
