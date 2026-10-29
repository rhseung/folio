import FolioDomain
import Foundation

/// Card candidates for one unit (docs/SPEC.md "퀴즈 카드 생성"). Shown to the user, who saves only the ones picked.
public struct QuizCardDrafts: StructuredResult, Equatable {
    public struct Draft: Codable, Sendable, Equatable {
        public var type: String
        public var category: String
        public var prompt: String
        public var options: [String]
        public var answer: String
        public var rubric: [String]

        public init(type: String, category: String, prompt: String, options: [String] = [], answer: String, rubric: [String] = []) {
            self.type = type
            self.category = category
            self.prompt = prompt
            self.options = options
            self.answer = answer
            self.rubric = rubric
        }

        /// The card to save, or nil when a choice card's answer isn't one of its options.
        public func card(unitId: UUID, device: DeviceID, at date: Date) -> QuizCard? {
            let type = CardType(rawValue: type) ?? .free
            var options = options
            if type == .trueFalse { options = QuizCard.trueFalseOptions }
            guard type != .choice && type != .trueFalse || options.contains(answer) else { return nil }
            return QuizCard(device: device, at: date, unitId: unitId, type: type, category: CardCategory(rawValue: category) ?? .concept,
                            prompt: prompt, options: type == .choice || type == .trueFalse ? options : [], answer: answer, rubric: rubric, source: .ai)
        }
    }

    public var cards: [Draft]

    static let types: [CardType] = [.free, .trueFalse, .choice, .fill, .proof]

    public static let schema = Schema.object(["cards": Schema.array(Schema.object([
        "type": Schema.enumeration(types.map(\.rawValue)),
        "category": Schema.enumeration(CardCategory.allCases.map(\.rawValue)),
        "prompt": Schema.string,
        "options": Schema.array(Schema.string),
        "answer": Schema.string,
        "rubric": Schema.array(Schema.string),
    ]))])
}

extension ClaudeClient {
    /// Asks for `count` cards on `unitTitle`. `context` holds the course summary and the unit's notes; it goes through
    /// `ContextBuilder` so the summary is cached and the notes are cut to the budget.
    public func makeCards(unitTitle: String, count: Int, type: CardType?, context: [ContextItem],
                          budgetTokens: Int = 60_000) async throws -> [QuizCardDrafts.Draft] {
        let built = ContextBuilder.build(context, budgetTokens: budgetTokens)
        let system = built.system + [.text("""
        You write quiz cards for a university student, from their own course notes. Each card tests one idea: a definition, \
        a theorem's statement, a proof, a counterexample, a computation or a concept. Write prompts and answers in the \
        language of the notes, math in LaTeX ($...$). The answer is a complete model answer. The rubric lists the elements \
        an answer must contain to be correct, one short phrase each. For "choice" give 4 options and use the exact text \
        of the correct option as the answer; for "true_false" the answer is "참" or "거짓" and options are empty.
        """)]
        let kind = type.map { " 유형은 모두 \($0.rawValue)." } ?? " 유형은 섞어서."
        let ask = ContentBlock.text("단원 \"\(unitTitle)\"에서 퀴즈 카드 \(count)장을 만들어 주세요.\(kind)")
        let messages = [Message(role: .user, content: built.userBlocks + [ask])]
        return try await run(.quizCards, QuizCardDrafts.self, system: system, messages: messages).cards
    }
}
