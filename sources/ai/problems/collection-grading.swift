import FolioCore
import FolioDomain
import Foundation

extension ClaudeClient {
    // 손으로 푼 문제집 한 벌을 한 번에 채점한다(#577). 사용자가 쪽과 문제를 짝짓지 않으므로 Claude가 칸 머리("<묶음> – Problem
    // <번호>")로 문제마다 풀이를 찾는다. 답이 없는 문제는 틀림이다. 답에 없는 문제는 돌려주지 않아 채점하지 못한 것으로 남는다.
    public func gradeCollection(_ problems: [CollectionProblem], submitted pdf: Data, mock: Bool) async throws -> [CollectionGrade] {
        var list = ""
        for (i, c) in problems.enumerated() {
            let p = c.problem
            list += "\n<item index=\"\(i + 1)\" label=\"\(c.set) – Problem \(p.number)\">"
            for g in c.stems { list += "\n<stem>\n\(g.text)\n</stem>" }
            list += "\n<problem>\n\(p.text)\n</problem>"
            if let key = p.answer { list += "\n<answer_key>\n\(key)\n</answer_key>" }
            list += p.solution.map { "\n<solution>\n\($0)\n</solution>" } ?? "\n<solution>(none: solve it yourself first)</solution>"
            list += "\n</item>"
        }
        let reasons = WrongReason.choices(mock: mock).map(\.rawValue).joined(separator: ", ")
        let content: [ContentBlock] = [
            .text("The student's handwritten work on the printed problem collection:"), .pdf(pdf),
            .text("The problems in the collection, in print order:" + list),
        ]
        let system: [ContentBlock] = [
            .text(
                """
                You grade a university student's handwritten work on a printed problem collection. Each problem was printed \
                in a box headed by its label ("<set> – Problem <number>") with space for the answer below it, so find the \
                work for each item under its box and on the following pages until the next box. Grade every item exactly \
                once and set "item" to its index. Compare the work with the solution when one is given; otherwise solve \
                the problem yourself first and compare with your own result. "correct" means the final result and the \
                essential reasoning are right. "partial" means the core idea is right but a step is missing, unjustified \
                or miscomputed. "wrong" otherwise, including blank or crossed-out work. For a mistake, set "reason" to the \
                most likely cause, one of: \(reasons). concept: does not know the idea or theorem; method: knows it but \
                picked the wrong approach; calculation: an arithmetic or algebra slip; misread: answered a different \
                question; time: stopped before finishing. Otherwise null. Write "feedback" in Korean as at most three short \
                sentences, naming the first wrong step. Set "page" to the PDF page (from 1) where the work starts, or null \
                when there is none.
                """, cache: true),
            .text(MathWriting.rule, cache: true),
        ]
        let reply = try await run(
            .collectionGrading, CollectionGrades.self, system: system, messages: [Message(role: .user, content: content)])
        var seen: Set<UUID> = []
        return reply.grades.compactMap { g in
            guard problems.indices.contains(g.item - 1) else { return nil }
            let p = problems[g.item - 1].problem
            guard seen.insert(p.id).inserted else { return nil }
            let grade = ProblemGrade(verdict: g.verdict, reason: g.verdict.isMistake ? g.reason : nil, feedback: g.feedback)
            return CollectionGrade(
                problem: p.id, outcome: GradeOutcome(grade: grade, basis: p.hasSolution || p.hasKey ? .solution : .claude), page: g.page)
        }
    }
}
