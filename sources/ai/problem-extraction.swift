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
    ) async throws -> [Problem] {
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
                each problem's full statement in the sheet's language with math in LaTeX ($...$ and $$...$$); describe a \
                figure in one sentence in brackets when the statement needs it. "page" is the 1-based PDF page the problem \
                starts on. Pick "format": true_false, choice (copy the options), short (a single value, expression or word) \
                or written (a derivation, proof or explanation). When a solution document is given, set "answer" for \
                true_false (참 or 거짓), choice (the exact option text) and short problems, copy the worked solution into \
                "solution", and set "solutionPage" to its 1-based page in the solution document. Otherwise leave them null. \
                Set "units" to the exact titles of the course units the problem tests, most specific first; never invent \
                a unit title. Set "lecturePages" to the one to three lecture pages (from <lectures>, inside the unit's page \
                range) where the concept the problem needs is taught, or [] when none fits. Skip cover pages, instructions \
                and blank answer space.
                """, cache: true)
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
        return drafts.problems.map { $0.problem(units: units, lectures: ids) }
    }
}
