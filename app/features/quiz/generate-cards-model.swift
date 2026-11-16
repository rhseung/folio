import FolioAI
import FolioActions
import FolioDomain
import Foundation
import Observation

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
        [(CardType?.none, String(localized: .quizGenerateMixed))]
            + [CardType.free, .proof, .choice, .trueFalse, .fill].map { (Optional($0), $0.label) }
    }

    func toggle(_ card: QuizCard) {
        if kept.contains(card.id) { kept.remove(card.id) } else { kept.insert(card.id) }
    }

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

    // 제목은 화면 문구가 아니라 Claude가 읽는 값이므로 쓴 그대로 둔다.
    private func cardContext() -> [ContextItem] {
        [ContextBuilder.courseSummary(course.file, now: .now)]
            + workspace.notes(for: unit, in: course.id).compactMap { note in
                (try? course.store.read(note)).map {
                    ContextItem(id: "note:\(note.title)", title: "노트 \(note.title)", tier: .focus, text: $0)
                }
            }
    }
}
