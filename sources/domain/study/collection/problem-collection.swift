import Foundation

// 고른 문제로 만드는 문제집과 풀이집 두 권이다. 모양은 사용자가 시험 대비로 쓰던 문제집을 따른다(#577). 문제집은 문제마다
// "Attempt" 칸과 풀이 자리를 두고, 풀이집은 같은 문제를 같은 차례로 두어 회색 상자의 문제 아래에 답과 풀이를 둔다.
public struct ProblemCollection: Sendable, Equatable {
    public enum Item: Sendable, Equatable {
        // 소문제들이 함께 보는 지문이다. 그 소문제들 앞에 한 번 둔다.
        case stem(ProblemGroup)
        case problem(Problem)
    }

    // 문제 묶음 하나다. 묶음마다 새 쪽을 연다.
    public struct Section: Sendable, Equatable {
        public var title: String
        // 그림을 잘라 올 문제지 PDF의 파일 이름이다. 빌드 폴더 안에서의 이름이고, 없으면 그림 없이 넣는다.
        public var sheet: String?
        public var items: [Item]

        public init(title: String, sheet: String? = nil, items: [Item]) {
            self.title = title
            self.sheet = sheet
            self.items = items
        }
    }

    // 표지와 머리말에 쓰는 과목 이름이다("EC4207 Graph Theory").
    public var course: String
    public var term: String?
    // 표지의 이름이다. 비어 있으면 표지에서 뺀다.
    public var author: String?
    public var sections: [Section]

    public init(course: String, term: String? = nil, author: String? = nil, sections: [Section]) {
        self.course = course
        self.term = term
        self.author = author
        self.sections = sections
    }

    public var problemCount: Int {
        sections.reduce(0) { n, s in n + s.items.count { if case .problem = $0 { true } else { false } } }
    }

    // 묶음마다 고른 문제를 문제지의 차례(`ProblemTree`)로 두고, 지문은 고른 소문제가 있을 때만 그 앞에 한 번 둔다. 묶음의 차례는
    // `sets`의 차례다. 고른 문제가 없는 묶음은 뺀다. `sheets`는 묶음 ID마다 빌드 폴더에 둔 문제지 PDF의 이름이다.
    public static func sections(sets: [ProblemSet], picked: Set<UUID>, sheets: [UUID: String] = [:]) -> [Section] {
        sets.compactMap { set in
            func walk(_ nodes: [ProblemTree.Node]) -> [Item] {
                nodes.flatMap { node -> [Item] in
                    let below = walk(node.children)
                    switch node.item {
                    case .group(let g): return below.isEmpty ? [] : [.stem(g)] + below
                    case .problem(let p): return (picked.contains(p.id) ? [.problem(p)] : []) + below
                    }
                }
            }
            let items = walk(ProblemTree(set).roots)
            return items.isEmpty ? nil : Section(title: set.title, sheet: sheets[set.id], items: items)
        }
    }

    // 학기를 표지에 쓰는 말이다("Fall 2026"). 인정학기는 학기 이름이 없다.
    public static func term(year: Int, _ term: Term) -> String? {
        let name: String? =
            switch term {
            case .spring: "Spring"  // strings: data, 문제집 PDF의 학기
            case .summer: "Summer"  // strings: data, 문제집 PDF의 학기
            case .fall: "Fall"  // strings: data, 문제집 PDF의 학기
            case .winter: "Winter"  // strings: data, 문제집 PDF의 학기
            case .credited: nil
            }
        return name.map { "\($0) \(year)" }
    }

    public var problemsTeX: String {
        let body = sections.flatMap { section in
            [ProblemCollectionTeX.problemSet(section.title)]
                + section.items.map { item in
                    switch item {
                    case .stem(let g):
                        "\\stem{\(Self.escaped(section.title))}{\(Self.stemName(g))}{%\n\(Self.body(g.text, g.figures, sheet: section.sheet))}"
                    case .problem(let p):
                        "\\prob[\(p.layoutSize.rawValue)]{\(Self.escaped(section.title))}{\(Self.escaped(p.number))}{\(Self.tag(p))}{%\n"
                            + Self.statement(p, sheet: section.sheet) + "}"
                    }
                }
        }
        return Self.document(
            ProblemCollectionTeX.problems(course: Self.escaped(course), cover: cover(ProblemCollectionTeX.problemsSubtitle)), body)
    }

    public var solutionsTeX: String {
        let body = sections.flatMap { section in
            [ProblemCollectionTeX.problemSet(section.title)]
                + section.items.map { item in
                    switch item {
                    case .stem(let g):
                        "\\solstem{\(Self.escaped(section.title))}{\(Self.stemName(g))}{%\n\(Self.body(g.text, g.figures, sheet: section.sheet))}"
                    case .problem(let p):
                        "\\sol{\(Self.escaped(section.title))}{\(Self.escaped(p.number))}{\(Self.tag(p))}{%\n"
                            + Self.statement(p, sheet: section.sheet) + "}{%\n" + Self.solution(p) + "}"
                    }
                }
        }
        return Self.document(
            ProblemCollectionTeX.solutions(course: Self.escaped(course), cover: cover(ProblemCollectionTeX.solutionsSubtitle)), body)
    }

    // 묶음 제목은 파일 이름에서 오고, macOS의 파일 이름은 한글을 자모로 풀어 둔다(NFD). TeX은 푼 자모를 따로 그리므로 모은다.
    private static func document(_ head: String, _ body: [String]) -> String {
        (head + body.joined(separator: "\n\n") + "\n\n\\end{document}\n").precomposedStringWithCanonicalMapping
    }

    private func cover(_ subtitle: String) -> String {
        let line = [term, author].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .map(Self.escaped).joined(separator: " \\quad ")
        return ProblemCollectionTeX.cover(title: Self.escaped(course), subtitle: subtitle, line: line.isEmpty ? nil : line)
    }

    // 문제의 글은 이미 LaTeX 본문이라 그대로 넣는다(#575). 사람이 적은 이름만 글자로 바꾼다.
    static func escaped(_ text: String) -> String { NoteTemplate.texEscaped(text) }

    // 제목이 없는 지문은 문제 번호처럼 부른다("Problem 2"). 지문의 번호는 소문제들이 상위로 가리키는 문제 번호이기 때문이다.
    static func stemName(_ g: ProblemGroup) -> String {
        let title = (g.title ?? "").trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? "Problem " + escaped(g.number) : escaped(title)  // strings: data, 문제집 PDF의 지문 머리
    }

    // 배점이 있으면 칸 머리에 적는다("(15pt)").
    static func tag(_ p: Problem) -> String {
        guard let points = p.points, points > 0 else { return "" }
        let n = points.rounded() == points ? String(Int(points)) : String(points)
        return "(\(n)pt)"  // strings: data, 문제집 PDF의 배점 표시
    }

    static func statement(_ p: Problem, sheet: String?) -> String {
        var parts = [p.text.trimmingCharacters(in: .whitespacesAndNewlines)]
        if p.format == .choice, !p.options.isEmpty {
            parts.append(
                (["\\begin{enumerate}[label=(\\alph*),leftmargin=8mm,topsep=2mm,itemsep=1mm]"]
                    + p.options.map { "\\item " + $0 } + ["\\end{enumerate}"]).joined(separator: "\n"))
        }
        return body(parts.joined(separator: "\n\n"), p.figures, sheet: sheet)
    }

    static func body(_ text: String, _ figures: [ProblemRegion], sheet: String?) -> String {
        var parts = [text.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        if let sheet { parts += figures.map { ProblemCollectionTeX.figure(sheet, $0) } }
        return parts.joined(separator: "\n\n") + "\n"
    }

    static func solution(_ p: Problem) -> String {
        var parts: [String] = []
        if let answer = p.answer?.trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty {
            parts.append("\\answer{\(p.format == .trueFalse ? ProblemCollectionTeX.trueFalse(answer) : answer)}")
        }
        if let solution = p.solution?.trimmingCharacters(in: .whitespacesAndNewlines), !solution.isEmpty {
            parts.append("\\method{}\n" + solution + "\n\n\\qedsym")
        } else if let page = p.solutionPage {
            parts.append(ProblemCollectionTeX.solutionPage(page))
        }
        return (parts.isEmpty ? [ProblemCollectionTeX.noSolution] : parts).joined(separator: "\n\n") + "\n"
    }
}
