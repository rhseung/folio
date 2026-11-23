import FolioCore
import FolioDomain
import Foundation

extension ClaudeClient {
    // 문제지에서 문제를 옮겨 쓴다. 풀이 파일이 있으면 정답과 풀이도 함께 옮긴다. 결과는 초안이고, 사용자가 받기 전에는
    // 과목에 들어가지 않는다. 단원마다 렉처 쪽 구간과 그 쪽의 제목을 주어, Claude가 문제마다 개념이 나온 렉처 쪽을 고르게
    // 한다. 앱은 그 쪽으로 단원을 잇는다(`ProblemExtraction.linked`).
    public func extractProblems(
        sheet: ProblemDocument, solution: ProblemDocument?, units: [FolioDomain.Unit], lectures: LectureOutline = LectureOutline(),
        source: ProblemSource
    ) async throws -> ExtractedProblems {
        let names = Dictionary(uniqueKeysWithValues: lectures.lectures.enumerated().map { ("L\($0.offset + 1)", $0.element) })
        let key = Dictionary(uniqueKeysWithValues: names.map { ($0.value.materialId, $0.key) })
        let outline = UnitTree.outline(units).map { row in
            let ranges = row.unit.lecturePages.compactMap { r in
                key[r.materialId].map { "\($0) p.\(r.pages.lowerBound)–\(r.pages.upperBound)" }
            }
            return String(repeating: "  ", count: row.depth) + "- " + row.unit.title
                + (ranges.isEmpty ? "" : " (\(ranges.joined(separator: ", ")))")
        }
        let pages = names.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }.flatMap { name, lecture in
            ["\(name) = \(lecture.name)"] + lecture.pages.map { "\(name) p.\($0.number): \($0.title ?? "")" }
        }
        let system: [ContentBlock] = [
            .text(
                """
                You transcribe every problem of a university problem sheet (\(source.rawValue)) so a student can solve them \
                one by one. Keep the sheet's own numbering; a sub-question like 3(a) gets number "3a" and parent "3". Copy \
                each problem's full statement in English as LaTeX body source (no preamble); when the sheet is in another \
                language, translate it faithfully, keeping every formula, symbol, number and label as it is. Use only this LaTeX: a blank line between paragraphs and \\\\ for a line break, never wrapping a \
                line by hand because every newline shows as a line break; \\textbf{}, \\emph{}, \\textit{}, \
                \\underline{}, \\texttt{} for the sheet's emphasis; itemize and enumerate, at most two levels deep, writing \
                any label other than 1. 2. or a bullet explicitly as \\item[(a)] or \\item[(i)] and never [label=...] options; \
                the escapes \\% \\& \\# \\_ \\$ \\{ \\}, ~, -- and ---; math inline in $...$ and displayed in $$...$$ or \
                align, align* or gather. Never use tables, \\includegraphics or figure, \\section, spacing commands, footnotes, \
                verbatim, custom macros or Markdown. "groups" text, options and "solution" are in English too and use the same \
                LaTeX; each option is one line without lists. Never describe \
                a figure in words (no "[Figure: ...]"): the app shows the figure itself, cut from the PDF, from the boxes you \
                give. "page" is the 1-based PDF page the problem starts on. Boxes locate things on a PDF page: "page" is \
                1-based and x, y, width, height are fractions of the page's width and height measured from its top-left \
                corner. "region" is the box holding the whole problem; "figures" are the boxes of each drawing, graph, table \
                or diagram the problem needs to be solved, drawn tightly around the figure with its labels. The sheet is a \
                tree like folders: a stem that sub-problems hang under (a heading such as "Warm-up Problems", instructions, \
                or the numbered statement or figure that introduces sub-questions (a), (b)) goes in "groups", with "number" \
                the value its children use as "parent", a short "title" for the heading ("Warm-up") or null, its text, \
                region and figures, and "parent" set to the enclosing stem's number when stems nest (W -> W1 -> W1a). List \
                only the actual questions in "problems", in sheet order, and do not repeat a stem or its figures in its \
                children. Pick "format": true_false, choice (copy the options), short (a single value, expression or word) \
                or written (a derivation, proof or explanation). Pick "size" by how much writing a full answer takes, not by \
                format: half when the answer fits in half an A4 page, including short proofs, and full for long proofs, \
                case analyses or big computations. When a solution document is given, set "answer" for \
                true_false (참 or 거짓), choice (the exact option text) and short problems, copy the worked solution into \
                "solution", and set "solutionPage" to its 1-based page in the solution document. Otherwise leave them null. \
                Set "units" to the exact titles of the course units the problem tests, most specific first; never invent \
                a unit title. Set "lecturePages" to the one to three lecture pages (from <lectures>, inside the unit's page \
                range) where the concept the problem needs is taught, or [] when none fits. Skip cover pages, instructions \
                that belong to no problem, and blank answer space. For a LaTeX source, region is null and figures are empty.
                """, cache: true),
            .text(MathWriting.rule, cache: true),
        ]
        var content: [ContentBlock] = [
            .text(
                """
                <units>
                \(outline.isEmpty ? "(none)" : outline.joined(separator: "\n"))
                </units>
                <lectures>
                \(pages.isEmpty ? "(none)" : pages.joined(separator: "\n"))
                </lectures>
                """)
        ]
        content += sheet.blocks("Problem sheet")
        if let solution { content += solution.blocks("Solution document") }
        let drafts = try await run(.extractProblems, ProblemDrafts.self, system: system, messages: [Message(role: .user, content: content)])
        let ids = names.mapValues(\.materialId)
        return ExtractedProblems(
            problems: drafts.problems.map { $0.problem(units: units, lectures: ids) }, groups: (drafts.groups ?? []).map(\.group))
    }
}
