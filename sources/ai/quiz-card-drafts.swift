import FolioDomain
import Foundation

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

        public func card(unitId: UUID, device: DeviceID, at date: Date) -> QuizCard? {
            let type = CardType(rawValue: type) ?? .free
            var options = options
            if type == .trueFalse { options = QuizCard.trueFalseOptions }
            guard type != .choice && type != .trueFalse || options.contains(answer) else { return nil }
            return QuizCard(
                device: device, at: date, unitId: unitId, type: type, category: CardCategory(rawValue: category) ?? .concept,
                prompt: prompt, options: type == .choice || type == .trueFalse ? options : [], answer: answer, rubric: rubric, source: .ai)
        }
    }

    public var cards: [Draft]

    static let types: [CardType] = [.free, .trueFalse, .choice, .fill, .proof]

    public static let schema = Schema.object([
        "cards": Schema.array(
            Schema.object([
                "type": Schema.enumeration(types.map(\.rawValue)),
                "category": Schema.enumeration(CardCategory.allCases.map(\.rawValue)),
                "prompt": Schema.string,
                "options": Schema.array(Schema.string),
                "answer": Schema.string,
                "rubric": Schema.array(Schema.string),
            ]))
    ])
}
