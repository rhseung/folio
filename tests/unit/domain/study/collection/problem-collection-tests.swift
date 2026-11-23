import FolioCore
import FolioDomain
import Foundation
import PropertyBased
import Testing

struct ProblemCollectionTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func set(_ title: String, _ problems: [Problem], groups: [ProblemGroup] = []) -> ProblemSet {
        ProblemSet(device: device, at: now, title: title, problems: problems, groups: groups)
    }

    // 문제지: 1, 지문 2(2a, 2b), 3. 지문의 그림은 2쪽에 있다.
    var midterm: ProblemSet {
        let figure = ProblemRegion(page: 2, x: 0.2, y: 0.3, width: 0.5, height: 0.25)
        return set(
            "Midterm",
            [
                Problem(number: "1", points: 10, text: "Is $K_{3,3}$ planar?", format: .trueFalse),
                Problem(number: "2a", parent: "2", text: "State Hall's theorem.", format: .written, size: .half),
                Problem(number: "2b", parent: "2", text: "Decide whether $G$ has a perfect matching.", format: .written),
                Problem(number: "3", points: 2.5, text: "Find $\\chi(P)$.", format: .short, answer: "3", solution: "$P$ has an odd cycle."),
            ], groups: [ProblemGroup(number: "2", text: "Let $G$ be the graph below.", figures: figure.map { [$0] } ?? [])])
    }

    @Test func sectionsKeepTheSheetOrderAndPutAStemOnceBeforeItsPickedChildren() {
        let m = midterm, hw = set("HW 1", [Problem(number: "1", text: "x")])
        let ids = m.problems.map(\.id)
        // 고른 차례가 섞여 있어도 문제지의 차례로 둔다.
        let sections = ProblemCollection.sections(sets: [m, hw], picked: [ids[3], ids[2], ids[1]])
        #expect(sections.map(\.title) == ["Midterm"])
        #expect(sections[0].items.map(Self.label) == ["stem 2", "2a", "2b", "3"])

        // 지문의 소문제를 하나도 고르지 않으면 지문도 빠진다.
        let without = ProblemCollection.sections(sets: [m, hw], picked: [ids[0], ids[3], hw.problems[0].id])
        #expect(without.map { $0.items.map(Self.label) } == [["1", "3"], ["1"]])
    }

    // 고른 문제는 모두 한 번씩, 문제지의 풀기 차례(`ProblemTree.questions`)대로 들어가고, 지문은 그 소문제 바로 앞에 한 번 들어간다.
    @Test func everyPickedProblemAppearsOnceInSheetOrder() async {
        let m = midterm
        await propertyCheck(input: Gen.int(in: 0...15)) { mask in
            let picked = Set(m.problems.indices.filter { mask & (1 << $0) != 0 }.map { m.problems[$0].id })
            let items = ProblemCollection.sections(sets: [m], picked: picked).flatMap(\.items)
            let problems = items.compactMap { if case .problem(let p) = $0 { p.id } else { nil } }
            #expect(problems == ProblemTree(m).questions.map(\.id).filter(picked.contains))
            for (i, item) in items.enumerated() {
                guard case .stem(let g) = item else { continue }
                guard case .problem(let next) = items[safe: i + 1] else {
                    Issue.record("지문 뒤에 문제가 없다")
                    continue
                }
                #expect(next.parent == g.number)
                #expect(items.filter { if case .stem(let s) = $0 { s.id == g.id } else { false } }.count == 1)
            }
        }
    }

    @Test func theProblemsDocumentFollowsTheCollectionFormat() throws {
        let m = midterm
        let collection = ProblemCollection(
            course: "EC4207 Graph Theory", term: "Fall 2026", author: "Kim",
            sections: ProblemCollection.sections(sets: [m], picked: Set(m.problems.map(\.id)), sheets: [m.id: "sheet-1.pdf"]))
        let tex = collection.problemsTeX
        #expect(tex.contains("\\problemset{Midterm}{Midterm}{}"))
        // 크기를 정하지 않은 문제는 형식으로 고른다. 참·거짓은 반 쪽, 서술은 한 쪽이다. 정한 크기가 이긴다.
        #expect(tex.contains("\\prob[half]{Midterm}{1}{(10pt)}{%\nIs $K_{3,3}$ planar?\n}"))
        #expect(tex.contains("\\prob[half]{Midterm}{2a}{}"))
        #expect(tex.contains("\\prob[full]{Midterm}{2b}{}"))
        #expect(tex.contains("\\prob[half]{Midterm}{3}{(2.5pt)}"))
        #expect(
            tex.contains(
                "\\stem{Midterm}{Problem 2}{%\nLet $G$ be the graph below.\n\n\\sheetfigure{sheet-1.pdf}{2}{0.1900}{0.2900}{0.5200}{0.2700}\n}"
            ))
        #expect(tex.components(separatedBy: "\\stem{Midterm}").count == 2)
        let stem = try #require(tex.range(of: "\\stem{Midterm}")), first = try #require(tex.range(of: "{2a}"))
        #expect(stem.lowerBound < first.lowerBound)
        #expect(tex.contains("{\\small Fall 2026 \\quad Kim}"))
        #expect(tex.contains("EC4207 Graph Theory \\,--\\, Problem Collection"))
        #expect(tex.hasSuffix("\\end{document}\n"))
    }

    // 문제지 PDF가 없는 묶음(Claude가 쓴 문제)은 그림 없이 넣는다. 그림을 다시 그리지 않는다.
    @Test func withoutASheetFiguresAreLeftOut() {
        let m = midterm
        let tex = ProblemCollection(course: "C", sections: ProblemCollection.sections(sets: [m], picked: Set(m.problems.map(\.id))))
            .problemsTeX
        #expect(!tex.contains("\\sheetfigure{sheet"))
        #expect(tex.contains("Let $G$ be the graph below.\n}"))
    }

    @Test func theCoverLeavesOutAnEmptyNameAndEscapesTitles() {
        let s = set("HW #1 & 2", [Problem(number: "1_a", text: "$x$")])
        let tex = ProblemCollection(
            course: "MA1001 50% 미적분", term: nil, author: "  ", sections: ProblemCollection.sections(sets: [s], picked: [s.problems[0].id])
        )
        .problemsTeX
        let cover = tex.firstRange(of: "\\begin{center}").map { tex[$0.upperBound...] }?.split(separator: "\\end{center}").first ?? ""
        #expect(!cover.contains("\\quad") && !cover.isEmpty)
        #expect(tex.contains("{\\LARGE\\bfseries MA1001 50\\% 미적분}"))
        #expect(tex.contains("\\problemset{HW \\#1 \\& 2}{HW \\#1 \\& 2}{}"))
        #expect(tex.contains("{1\\_a}"))
    }

    // macOS의 파일 이름에서 온 제목은 한글이 자모로 풀려 있다(NFD). TeX이 자모를 따로 그리지 않게 모아서 쓴다.
    @Test func decomposedHangulIsComposed() {
        let title = "기말".decomposedStringWithCanonicalMapping
        let s = set(title, [Problem(number: "1", text: "x")])
        let tex = ProblemCollection(course: "C", sections: ProblemCollection.sections(sets: [s], picked: [s.problems[0].id])).problemsTeX
        #expect(tex.contains("\\problemset{기말}"))
        // Swift의 문자열 비교는 NFC와 NFD를 같게 보므로 풀린 자모(U+1100–U+11FF)가 남았는지 본다.
        #expect(!tex.unicodeScalars.contains { (0x1100...0x11FF).contains($0.value) })
    }

    @Test func theSolutionsDocumentPutsTheAnswerAndSolutionUnderTheStatement() {
        let m = midterm
        var noted = m.problems[1]
        noted.solutionPage = 4
        var withNote = m
        withNote.problems[1] = noted
        let tex = ProblemCollection(course: "C", sections: ProblemCollection.sections(sets: [withNote], picked: Set(m.problems.map(\.id))))
            .solutionsTeX
        #expect(
            tex.contains(
                "\\sol{Midterm}{3}{(2.5pt)}{%\nFind $\\chi(P)$.\n}{%\n\\answer{3}\n\n\\method{}\n$P$ has an odd cycle.\n\n\\qedsym\n}"))
        #expect(tex.contains("\\answer{거짓}") == false)
        #expect(tex.contains("See page 4 of the solution document."))
        #expect(
            tex.contains(
                "\\sol{Midterm}{2b}{}{%\nDecide whether $G$ has a perfect matching.\n}{%\n{\\color{taggray}No answer or solution on file.}\n}"
            ))
        #expect(tex.contains("\\solstem{Midterm}{Problem 2}"))
        #expect(tex.contains("\\usepackage{amsmath,amssymb,amsthm,mathtools,enumitem,xcolor,fancyhdr,xparse,graphicx,needspace}"))
    }

    // 참·거짓의 정답 값은 한국어 데이터지만 풀이집은 영어로 쓴다.
    @Test func trueFalseAnswersReadInEnglish() {
        let s = set("Q", [Problem(number: "1", text: "$K_5$ is planar.", format: .trueFalse, answer: "거짓")])
        let tex = ProblemCollection(course: "C", sections: ProblemCollection.sections(sets: [s], picked: [s.problems[0].id])).solutionsTeX
        #expect(tex.contains("\\answer{False}"))
    }

    @Test func choicesAreListedUnderTheStatement() {
        let s = set("Q", [Problem(number: "1", text: "Pick one.", format: .choice, options: ["$K_4$", "$C_5$"])])
        let tex = ProblemCollection(course: "C", sections: ProblemCollection.sections(sets: [s], picked: [s.problems[0].id])).problemsTeX
        #expect(
            tex.contains(
                "Pick one.\n\n\\begin{enumerate}[label=(\\alph*),leftmargin=8mm,topsep=2mm,itemsep=1mm]\n\\item $K_4$\n\\item $C_5$\n\\end{enumerate}"
            ))
    }

    @Test func theTermReadsInEnglish() {
        #expect(ProblemCollection.term(year: 2026, .fall) == "Fall 2026")
        #expect(ProblemCollection.term(year: 2027, .spring) == "Spring 2027")
        #expect(ProblemCollection.term(year: 2026, .credited) == nil)
    }

    // 크기는 정했을 때만 course.json에 쓴다. 크기가 생기기 전에 받은 문제의 파일이 바뀌지 않게 하려는 것이다.
    @Test func theSizeIsStoredOnlyWhenSet() throws {
        let plain = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(Problem(number: "1")))
        #expect(plain["size"] == nil)
        let sized = Problem(number: "1", size: .half)
        #expect(try JSONDecoder().decode(Problem.self, from: JSONEncoder().encode(sized)).size == .half)
        #expect(Problem(number: "1", format: .written).layoutSize == .full)
        #expect(Problem(number: "1", format: .short).layoutSize == .half)
        #expect(Problem(number: "1", format: .written, size: .half).layoutSize == .half)
    }

    static func label(_ item: ProblemCollection.Item) -> String {
        switch item {
        case .stem(let g): "stem " + g.number
        case .problem(let p): p.number
        }
    }
}

extension Array {
    fileprivate subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
