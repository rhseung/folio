import FolioAI
import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class SuggestCardsModel {
    struct Choice: Identifiable {
        var material: CardMaterial
        var title: String
        var detail: String
        var isAvailable: Bool
        var id: CardMaterial { material }
    }

    enum Kinds: Hashable, CaseIterable {
        case flip, trueFalse, both

        var kinds: [CardKind] {
            switch self {
            case .flip: [.flip]
            case .trueFalse: [.trueFalse]
            case .both: [.flip, .trueFalse]
            }
        }
    }

    let workspace: Workspace
    let course: LoadedCourse
    let unit: FolioDomain.Unit
    // 노트 옆 카드 칸에서 열면 그 정리 노트가 재료이고, 만든 카드를 그 노트에 잇는다. 단원에서 열면 단원에 이은 노트들이 재료다.
    let note: NoteFile?
    private let notes: [NoteFile]
    var material = CardMaterial.note
    var kinds = Kinds.both
    var count = 5
    var candidates: [StudyCard] = []
    var kept: Set<UUID> = []
    var busy = false
    var failure: String?
    var keyRejected = false

    init(workspace: Workspace, course: LoadedCourse, unit: FolioDomain.Unit, note: UUID? = nil) {
        self.workspace = workspace
        self.course = course
        self.unit = unit
        self.note = note.flatMap { course.store.note(id: $0, in: course.file) }
        notes = self.note.map { [$0] } ?? workspace.notes(for: unit, in: course.id)
        material = choices.first(where: \.isAvailable)?.material ?? .note
    }

    var hasKey: Bool { workspace.claudeReady && !keyRejected }
    var title: String { String(localized: .cardsSuggestTitle(note?.title ?? unit.title)) }
    var confirmTitle: String { String(localized: candidates.isEmpty ? .cardsSuggestMake : .cardsSuggestSave(kept.count)) }
    var footnote: String { String(localized: candidates.isEmpty ? .cardsSuggestNoteMake : .cardsSuggestNotePick) }
    var canConfirm: Bool {
        guard hasKey, !busy else { return false }
        return candidates.isEmpty ? choices.contains { $0.material == material && $0.isAvailable } : !kept.isEmpty
    }
    var countOptions: [(Int, String)] { [3, 5, 10].map { ($0, String(localized: .cardsCount($0))) } }
    var kindOptions: [(Kinds, String)] {
        [(.flip, CardKind.flip.label), (.trueFalse, CardKind.trueFalse.label), (.both, String(localized: .cardsSuggestKindsBoth))]
    }

    // MARK: Material

    // 쪽 구간은 노트에 이은 단원들에서 찾는다. 단원에서 열었거나 노트가 단원에 이어지지 않았으면 그 단원이다.
    private var units: [UUID] {
        let linked = note?.meta.unitIds.filter { id in course.file.units.contains { $0.id == id } } ?? []
        return linked.isEmpty ? [unit.id] : linked
    }

    private func pages(_ material: CardMaterial) -> [LecturePages] { course.file.cardPages(material, units: units) }

    var choices: [Choice] {
        let noteChoice =
            if let note {
                Choice(material: .note, title: String(localized: .cardsSuggestMaterialNote), detail: note.title, isAvailable: true)
            } else {
                Choice(
                    material: .note, title: String(localized: .cardsSuggestMaterialNotes),
                    detail: String(localized: notes.isEmpty ? .cardsSuggestNoNotes : .cardsSuggestNotesCount(notes.count)),
                    isAvailable: !notes.isEmpty)
            }
        return [noteChoice]
            + [
                (CardMaterial.lecture, String(localized: .cardsSuggestMaterialLecture)),
                (.textbook, String(localized: .cardsSuggestMaterialTextbook)),
            ]
            .map { material, title in
                let pages = pages(material)
                return Choice(material: material, title: title, detail: describe(pages), isAvailable: !pages.isEmpty)
            }
    }

    private func describe(_ pages: [LecturePages]) -> String {
        guard let first = pages.first else { return String(localized: .cardsSuggestNoPages) }
        let name = (first.path as NSString).lastPathComponent
        let one = String(localized: .cardsSuggestPages(name, first.first ?? 1, first.last ?? 1))
        return pages.count > 1 ? String(localized: .cardsSuggestMoreFiles(one, pages.count - 1)) : one
    }

    // MARK: Making

    func toggle(_ card: StudyCard) {
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
        let (material, store, pages) = (material, course.store, pages(material))
        let texts = material == .note ? notes.compactMap { note in (try? course.store.read(note)).map { (note.title, $0) } } : []
        // 절은 정리 노트 하나가 재료일 때만 준다. 여러 노트의 절은 어느 노트의 것인지 가릴 수 없다.
        let sections =
            note != nil && material == .note
            ? (texts.first.map { NoteOutline($0.1).entries.filter { $0.level <= NoteOutline.depth }.map(\.anchor) } ?? []) : []
        let existing = (workspace.study(of: course.id)?.allCards ?? []).map(\.card)
            .filter { $0.unitId == unit.id || (note?.meta.id != nil && $0.noteId == note?.meta.id) }.map(\.front)
        let request = CardRequest(
            title: note?.title ?? unit.title, material: material, kinds: kinds.kinds, count: count, existing: existing, sections: sections)
        let summary = ContextBuilder.courseSummary(course.file, now: workspace.now)
        // 쪽이 한 파일에서만 왔을 때 카드에 그 파일과 쪽을 남긴다.
        let files = Set(pages.compactMap(\.materialId))
        let (unitId, noteId, device, now) = (unit.id, note?.meta.id, workspace.device, workspace.now)
        Task {
            do {
                let paged = pages.isEmpty ? "" : await Task.detached { store.pagedText(pages) }.value
                let context = [summary] + Self.context(material, notes: texts, paged: paged)
                let drafts = try await client.suggestCards(request, context: context)
                candidates = drafts.compactMap {
                    $0.card(
                        unitId: unitId, noteId: noteId, sections: sections, materialId: files.count == 1 ? files.first : nil,
                        device: device,
                        at: now)
                }
                kept = Set(candidates.map(\.id))
                if candidates.isEmpty { failure = String(localized: .cardsSuggestEmpty) }
            } catch ClaudeError.missingAPIKey {
                keyRejected = true
            } catch {
                failure = String(localized: .cardsSuggestFailed("\(error)"))
            }
            busy = false
        }
    }

    func savePicked() -> Bool {
        let picked = candidates.filter { kept.contains($0.id) }
        return workspace.run(CardSave(course: course.id, cards: picked, movedFrom: nil)) != nil
    }

    // 제목은 화면 문구가 아니라 Claude가 읽는 값이므로 쓴 그대로 둔다.
    private static func context(_ material: CardMaterial, notes: [(title: String, text: String)], paged: String) -> [ContextItem] {
        switch material {
        case .note:
            notes.map {
                ContextItem(
                    id: "note:\($0.title)",
                    title: "노트 \($0.title)",  // strings: data, Claude가 읽는 제목
                    tier: .focus, text: $0.text)
            }
        case .lecture: [ContextItem(id: "lecture", title: "lecture pages", tier: .focus, text: paged)]  // strings: data, Claude가 읽는 제목
        case .textbook: [ContextItem(id: "textbook", title: "textbook pages", tier: .focus, text: paged)]  // strings: data, Claude가 읽는 제목
        }
    }
}
