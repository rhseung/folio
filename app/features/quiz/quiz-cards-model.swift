import FolioActions
import FolioAI
import FolioDomain
import Foundation
import Observation

/// `original` is nil for a new one.
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
        var card = original ?? QuizCard(device: device, at: .now, unitId: unitId, type: type, category: category, prompt: prompt, answer: answer)
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

@MainActor @Observable
final class CardEditorModel {
    let workspace: Workspace
    let course: LoadedCourse
    var draft: CardDraft

    init(workspace: Workspace, course: LoadedCourse, draft: CardDraft) {
        self.workspace = workspace
        self.course = course
        self.draft = draft
    }

    var title: String { String(localized: draft.original == nil ? .quizCardAdd : .quizCardEdit) }
    var deleteTitle: String? { draft.original == nil ? nil : String(localized: .quizCardRemove) }

    func unitOptions(_ units: [FolioDomain.Unit]) -> [PickOption<UUID>] {
        UnitTree.outline(units).map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) }
    }

    func saveCard() -> Bool {
        let card = draft.card(device: workspace.device)
        return workspace.run(QuizCardSave(course: course.id, cards: [card], movedFrom: draft.original?.unitId)) != nil
    }

    func remove() {
        if let card = draft.original { workspace.run(QuizCardRemove(course: course.id, unit: card.unitId, card: card.id)) }
    }
}

@MainActor @Observable
final class GenerateCardsModel {
    let workspace: Workspace
    let course: LoadedCourse
    let unit: FolioDomain.Unit
    var count = 5
    var type: CardType?
    var candidates: [QuizCard] = []
    var kept: Set<UUID> = []
    var busy = false
    var failure: String?
    var keyRejected = false

    init(workspace: Workspace, course: LoadedCourse, unit: FolioDomain.Unit) {
        self.workspace = workspace
        self.course = course
        self.unit = unit
    }

    var hasKey: Bool { workspace.claudeReady && !keyRejected }
    var title: String { String(localized: .quizGenerateTitle(unit.title)) }
    var confirmTitle: String { String(localized: candidates.isEmpty ? .quizGenerateMake : .quizGenerateSave(kept.count)) }
    var note: String { String(localized: candidates.isEmpty ? .quizGenerateNoteMake : .quizGenerateNotePick) }
    var canConfirm: Bool { hasKey && !busy && (candidates.isEmpty || !kept.isEmpty) }
    var countOptions: [(Int, String)] { [3, 5, 10, 15].map { ($0, String(localized: .quizCardCount($0))) } }
    var typeOptions: [(CardType?, String)] {
        [(CardType?.none, String(localized: .quizGenerateMixed))] + [CardType.free, .proof, .choice, .trueFalse, .fill].map { (Optional($0), $0.label) }
    }

    func toggle(_ card: QuizCard) {
        if kept.contains(card.id) { kept.remove(card.id) } else { kept.insert(card.id) }
    }

    /// True once the picked cards are saved and the sheet can close.
    func confirm() -> Bool {
        if candidates.isEmpty {
            make()
            return false
        }
        return savePicked()
    }

    func make() {
        busy = true
        failure = nil
        let client = workspace.claude(for: course)
        let context = cardContext()
        let (unitId, device, title, count, type) = (unit.id, workspace.device, unit.title, count, type)
        Task {
            do {
                let drafts = try await client.makeCards(unitTitle: title, count: count, type: type, context: context)
                candidates = drafts.compactMap { $0.card(unitId: unitId, device: device, at: .now) }
                kept = Set(candidates.map(\.id))
                if candidates.isEmpty { failure = String(localized: .quizGenerateEmpty) }
            } catch ClaudeError.missingAPIKey {
                keyRejected = true
            } catch {
                failure = String(localized: .quizGenerateFailed("\(error)"))
            }
            busy = false
        }
    }

    func savePicked() -> Bool {
        let picked = candidates.filter { kept.contains($0.id) }
        return workspace.run(QuizCardSave(course: course.id, cards: picked)) != nil
    }

    /// The titles are what Claude reads, not UI, so they stay as written.
    private func cardContext() -> [ContextItem] {
        [ContextBuilder.courseSummary(course.file, now: .now)] + workspace.notes(for: unit, in: course.id).compactMap { note in
            (try? course.store.read(note)).map { ContextItem(id: "note:\(note.title)", title: "노트 \(note.title)", tier: .focus, text: $0) }
        }
    }
}
