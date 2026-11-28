import FolioCore
import FolioDomain
import Foundation

extension ClaudeClient {
    // 카드는 그대로 알아야 하는 것(용어, 정리의 내용, 공식, 헷갈리는 것의 차이, 자주 하는 실수)만 만든다. 풀이 연습은 문제가 맡는다.
    public func suggestCards(_ request: CardRequest, context: [ContextItem], budgetTokens: Int = 60_000) async throws -> [CardDrafts.Draft]
    {
        let built = ContextBuilder.build(context, budgetTokens: budgetTokens)
        let system =
            built.system + [
                .text(
                    """
                    You write concept cards for a university student from their own course material. A card checks one \
                    thing the student must know exactly: a term and its definition, the statement of a theorem with its \
                    conditions, a formula, the difference between two things that are easy to confuse, or a mistake \
                    students often make. Do not write problems to solve; those come from problem sheets.

                    There are two kinds of card, and "kind" says which.
                    - "flip": "front" is a short cue and "back" is the complete fact. "answer" is null.
                    - "true_false": "front" is one statement that is plainly true or plainly false, "answer" is true or \
                    false, and "back" is one line saying why. Write false statements a student could believe: a dropped \
                    condition, a swapped quantifier, the converse, or a property of the concept it is confused with. Do \
                    not negate a true sentence mechanically. Make about half of the true_false cards false.

                    Write only the kinds you are asked for, in the language of the material. Take every card from the \
                    material you are given and from nothing else. When a card comes from a numbered page, set "page" to \
                    that 1-based page, otherwise null. When you are given the sections of a note, set "section" to the \
                    title of the section the card comes from, copied exactly from the list, or null when none fits; \
                    otherwise null. Do not repeat a card the student already has.
                    """),
                .text(MathWriting.rule),
            ]
        let messages = [Message(role: .user, content: built.userBlocks + [.text(Self.ask(request))])]
        return try await run(.cardSuggestions, CardDrafts.self, system: system, messages: messages).cards
    }

    static func ask(_ request: CardRequest) -> String {
        let source =
            switch request.material {
            case .note: "정리 노트 \"\(request.title)\"의 용어, 정리의 내용, 공식, 헷갈리는 것 비교, 자주 하는 실수에서"
            case .lecture: "\"\(request.title)\"의 렉처 쪽에서"
            case .textbook: "\"\(request.title)\"의 교재 쪽에서"
            }
        let kinds =
            switch (request.kinds.contains(.flip), request.kinds.contains(.trueFalse)) {
            case (true, true): "앞뒤 카드(flip)와 참거짓 카드(true_false)를 섞어 주세요."
            case (false, true): "참거짓 카드(true_false)만 만들어 주세요."
            default: "앞뒤 카드(flip)만 만들어 주세요."
            }
        var lines = ["\(source) 카드 \(request.count)장을 만들어 주세요. \(kinds)"]
        if !request.sections.isEmpty { lines += ["노트의 절:"] + request.sections.map { "- " + $0 } }
        if !request.existing.isEmpty { lines += ["이미 있는 카드 앞면:"] + request.existing.map { "- " + $0 } }
        return lines.joined(separator: "\n")
    }
}
