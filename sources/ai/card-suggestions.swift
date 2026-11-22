import FolioCore
import FolioDomain
import Foundation

extension ClaudeClient {
    // 카드는 문제로 묻기 어려운 것(정의, 정리의 진술, 기호, 조건)만 만든다. 풀이 연습은 문제가 맡는다.
    public func suggestCards(unitTitle: String, count: Int, existing: [String], context: [ContextItem], budgetTokens: Int = 60_000)
        async throws -> [CardDrafts.Draft]
    {
        let built = ContextBuilder.build(context, budgetTokens: budgetTokens)
        let system =
            built.system + [
                .text(
                    """
                    You write flash cards for a university student from their own course material. A card holds one fact \
                    to remember: a definition, the exact statement of a theorem with its conditions, a notation, or a key \
                    formula. Do not write problems to solve; those come from problem sheets. The front is a short cue, the \
                    back is the complete fact. Write in the language of the material, math in LaTeX ($...$). When the fact \
                    comes from a numbered page of a lecture file, set "page" to that 1-based page, otherwise null. Do not \
                    repeat a card the student already has.
                    """)
            ]
        let have = existing.isEmpty ? "" : "\n이미 있는 카드 앞면:\n" + existing.map { "- " + $0 }.joined(separator: "\n")
        let ask = ContentBlock.text("단원 \"\(unitTitle)\"의 카드 \(count)장을 만들어 주세요.\(have)")
        let messages = [Message(role: .user, content: built.userBlocks + [ask])]
        return try await run(.cardSuggestions, CardDrafts.self, system: system, messages: messages).cards
    }
}
