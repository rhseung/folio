import FolioAI
import FolioActions
import FolioDomain
import Foundation
import Observation

struct CardDraft: Identifiable {
    var id = UUID()
    var original: QuizCard?
    var unitId: UUID
    var type: CardType = .free
    var category: CardCategory = .definition
    var prompt = ""
    var answer = ""
    var options = ""
    var rubric = ""

    init(unitId: UUID) {
        self.unitId = unitId
    }

    init(_ card: QuizCard) {
        original = card
        unitId = card.unitId
        type = card.type
        category = card.category
        prompt = card.prompt
        answer = card.answer
        options = card.type == .choice ? card.options.joined(separator: "\n") : ""
        rubric = card.rubric.joined(separator: "\n")
    }

    var optionList: [String] {
        switch type {
        case .trueFalse: QuizCard.trueFalseOptions
        case .choice: lines(options)
        default: []
        }
    }

    var isValid: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !answer.isEmpty
            && (!(type == .choice || type == .trueFalse) || optionList.contains(answer))
    }

    func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func card(device: DeviceID) -> QuizCard {
        var card =
            original ?? QuizCard(device: device, at: .now, unitId: unitId, type: type, category: category, prompt: prompt, answer: answer)
        card.unitId = unitId
        card.type = type
        card.category = category
        card.prompt = prompt
        card.answer = answer
        card.options = optionList
        card.rubric = lines(rubric)
        card.touch(by: device, at: .now)
        return card
    }
}
