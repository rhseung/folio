import FolioCore
import FolioDomain
import Foundation

extension ClaudeClient {
    // 풀이가 있으면 풀이에 맞춰 채점하고, 없으면 Claude가 스스로 푼 답과 견준다. 어느 쪽인지는 부르는 쪽이 근거로 남긴다.
    public func gradeProblem(_ problem: Problem, answer: String?, answerImages: [Data] = [], pageImage: Data? = nil) async throws
        -> ProblemGrade
    {
        var content: [ContentBlock] = []
        if let pageImage { content += [.text("The problem as printed:"), .image(pageImage, mediaType: "image/jpeg")] }
        if !answerImages.isEmpty {
            content.append(.text("The student's handwritten answer, page by page:"))
            content += answerImages.map { .image($0, mediaType: "image/png") }
        }
        content.append(
            .text(
                """
                <problem number="\(problem.number)">\n\(problem.text)\n</problem>
                \(problem.answer.map { "<answer_key>\n\($0)\n</answer_key>" } ?? "")
                \(problem.solution.map { "<solution>\n\($0)\n</solution>" } ?? "<solution>(none: solve it yourself first)</solution>")
                <student_answer>\n\(answer ?? (answerImages.isEmpty ? "(blank)" : "(handwriting above)"))\n</student_answer>
                """))
        let system: [ContentBlock] = [
            .text(
                """
                You grade one answer of a university student. Compare it with the solution when one is given; otherwise \
                solve the problem yourself first and compare with your own result. "correct" means the final result and \
                the essential reasoning are right. "partial" means the core idea is right but a step is missing, \
                unjustified or miscomputed. "wrong" otherwise, including a blank answer. For a mistake, set "reason" to the \
                most likely cause: concept (does not know the idea or theorem), method (knows it but picked the wrong \
                approach), calculation (an arithmetic or algebra slip), misread (answered a different question) or time \
                (stopped before finishing). Otherwise null. Write "feedback" in Korean as at most three short sentences, \
                naming the first wrong step. For handwriting, number lines top to bottom across the images and point at \
                the lines that cause the problem in "lines".
                """, cache: true),
            .text(MathWriting.rule, cache: true),
        ]
        return try await run(.grading, ProblemGrade.self, system: system, messages: [Message(role: .user, content: content)])
    }

    // 단답이 정답과 글자가 다를 때만 묻는다. 같은 값을 다르게 쓴 답(1/2와 0.5)을 틀렸다고 하지 않기 위해서다.
    public func sameAnswer(_ answer: String, key: String, problem: String) async throws -> Bool {
        let system: [ContentBlock] = [
            .text(
                "You decide whether a student's short answer means the same as the answer key for the problem, allowing "
                    + "equivalent forms (1/2 and 0.5, reordered sets, a synonym). Reply same=false when unsure.")
        ]
        let content: [ContentBlock] = [
            .text("<problem>\n\(problem)\n</problem>\n<key>\(key)</key>\n<answer>\(answer)</answer>")
        ]
        return try await run(.sameAnswer, SameAnswer.self, system: system, messages: [Message(role: .user, content: content)]).same
    }
}
