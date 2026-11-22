import FolioCore
import FolioDomain
import Foundation

extension ClaudeClient {
    // 문제지 PDF에서 문제를 옮겨 쓴다. 풀이 PDF가 있으면 정답과 풀이도 함께 옮긴다. 결과는 초안이고, 사용자가 받기 전에는
    // 과목에 들어가지 않는다.
    public func extractProblems(sheet: Data, solution: Data?, units: [FolioDomain.Unit], source: ProblemSource) async throws -> [Problem] {
        let outline = UnitTree.outline(units).map { String(repeating: "  ", count: $0.depth) + "- " + $0.unit.title }
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
                a unit title. Skip cover pages, instructions and blank answer space.
                """, cache: true)
        ]
        var content: [ContentBlock] = [
            .text("<units>\n\(outline.isEmpty ? "(none)" : outline.joined(separator: "\n"))\n</units>\nProblem sheet:"),
            .pdf(sheet),
        ]
        if let solution { content += [.text("Solution document:"), .pdf(solution)] }
        let drafts = try await run(.extractProblems, ProblemDrafts.self, system: system, messages: [Message(role: .user, content: content)])
        return drafts.problems.map { $0.problem(units: units) }
    }
}
