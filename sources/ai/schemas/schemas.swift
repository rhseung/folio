import FolioDomain
import Foundation

extension ClaudeClient {
    public func run<T: StructuredResult>(_ task: ClaudeTask, _ type: T.Type, system: [ContentBlock], messages: [Message]) async throws -> T
    {
        try await structured(task, as: type, schema: T.schema, system: system, messages: messages)
    }

    public func grade(
        question: String, modelAnswer: String, rubric: [String], answer: String?, answerImages: [Data] = [],
        rules: String
    ) async throws -> GradingResult {
        var content: [ContentBlock] = answerImages.map { .image($0, mediaType: "image/png") }
        content.append(
            .text(
                """
                <question>\n\(question)\n</question>
                <model_answer>\n\(modelAnswer)\n</model_answer>
                <rubric>\n\(rubric.map { "- " + $0 }.joined(separator: "\n"))\n</rubric>
                <answer>\n\(answer ?? "(손글씨 이미지)")\n</answer>
                """))
        let system: [ContentBlock] = [
            .text(
                """
                You grade a university student's answer. Judge it against the rubric: an answer missing any rubric element is \
                not "correct". Use "partial" when the core idea is right but an element is missing or a step is unjustified. \
                List each missing element verbatim from the rubric. Write the feedback in Korean, at most three sentences. \
                For handwriting, number lines top to bottom across the images and point at the lines that cause problems.
                \(rules)
                """, cache: true)
        ]
        return try await run(.grading, GradingResult.self, system: system, messages: [Message(role: .user, content: content)])
    }
}
