import FolioDomain
import Foundation

extension ClaudeClient {
    public func makeCards(
        unitTitle: String, count: Int, type: CardType?, context: [ContextItem],
        budgetTokens: Int = 60_000
    ) async throws -> [QuizCardDrafts.Draft] {
        let built = ContextBuilder.build(context, budgetTokens: budgetTokens)
        let system =
            built.system + [
                .text(
                    """
                    You write quiz cards for a university student, from their own course notes. Each card tests one idea: a definition, \
                    a theorem's statement, a proof, a counterexample, a computation or a concept. Write prompts and answers in the \
                    language of the notes, math in LaTeX ($...$). The answer is a complete model answer. The rubric lists the elements \
                    an answer must contain to be correct, one short phrase each. For "choice" give 4 options and use the exact text \
                    of the correct option as the answer; for "true_false" the answer is "참" or "거짓" and options are empty.
                    """)
            ]
        let kind = type.map { " 유형은 모두 \($0.rawValue)." } ?? " 유형은 섞어서."
        let ask = ContentBlock.text("단원 \"\(unitTitle)\"에서 퀴즈 카드 \(count)장을 만들어 주세요.\(kind)")
        let messages = [Message(role: .user, content: built.userBlocks + [ask])]
        return try await run(.quizCards, QuizCardDrafts.self, system: system, messages: messages).cards
    }
}
