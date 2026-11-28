import FolioActions
import FolioDomain
import FolioMarkdown
import Foundation
import Observation

@MainActor @Observable
final class NoteCardsModel {
    // 이 칸을 연 동안 카드가 놓인 면이다. 넘긴 기록은 로그에 있고, 이 값은 답한 카드를 답과 함께 보이게 한다.
    enum Face: Equatable {
        case front
        case back
        // 참거짓 카드는 고른 답을 함께 든다.
        case answered(known: Bool, picked: Bool?)

        var isAnswered: Bool { if case .answered = self { true } else { false } }
    }

    struct Group: Identifiable {
        var section: String?
        var title: String
        var cards: [CourseStudy.CardRecord]
        var progress: PlanProgress
        var id: String { section ?? "" }
    }

    let workspace: Workspace
    let courseId: UUID
    let noteId: UUID
    private(set) var outline: [NoteOutline.Entry] = []
    private(set) var faces: [UUID: Face] = [:]
    // 절 묶음을 누르거나 카드에 답하면 그 절이 "이 절"이 된다. 정한 적이 없으면 아직 넘기지 않은 첫 카드의 절이다.
    private var focus: String??

    init(workspace: Workspace, courseId: UUID, noteId: UUID) {
        self.workspace = workspace
        self.courseId = courseId
        self.noteId = noteId
        load()
    }

    var course: LoadedCourse? { workspace.course(courseId) }
    private var study: CourseStudy? { workspace.study(of: courseId) }
    private var entry: NoteEntry? { course?.file.notes.first { $0.id == noteId } }

    var exists: Bool { entry != nil }
    var noteTitle: String { entry?.title ?? "" }
    var changeKey: Int { workspace.notesRevision }

    // 절은 노트 파일의 제목에서 읽는다. 노트를 고치면 다시 읽는다.
    func load() {
        guard let course, let note = course.store.note(id: noteId, in: course.file), note.format == .markdown,
            let text = try? course.store.read(note)
        else {
            outline = []
            return
        }
        outline = NoteOutline(text).entries
    }

    // MARK: The deck

    var groups: [Group] {
        (study?.noteDeck(noteId, sections: outline.map(\.anchor)).groups ?? []).map { group in
            let title = group.section.flatMap { anchor in outline.first { $0.anchor == anchor }?.title }
            return Group(
                section: group.section, title: title ?? String(localized: .noteCardsWholeNote), cards: group.cards, progress: group.progress
            )
        }
    }

    // 고르거나 답한 절이 없어진 뒤에도(절 제목을 고쳤다) 묶음 하나를 가리키도록 지금 묶음에서 찾는다.
    func focused(in groups: [Group]) -> Group? {
        if let focus, let group = groups.first(where: { $0.section == focus }) { return group }
        let since = study?.readStart(ofNote: noteId)
        return groups.first { $0.cards.contains { !$0.isRead(since: since) } } ?? groups.first
    }

    // 키가 누르는 카드다. "이 절"에서 시작해 이번에 답하지 않은 카드를 차례로 본다.
    func current(in groups: [Group]) -> UUID? {
        guard let focused = focused(in: groups), let start = groups.firstIndex(where: { $0.id == focused.id }) else { return nil }
        let ordered = (groups[start...] + groups[..<start]).flatMap(\.cards)
        return ordered.first { !face(of: $0.card).isAnswered }?.card.id
    }

    func subtitle(_ groups: [Group]) -> String {
        let (done, total) = (groups.reduce(0) { $0 + $1.progress.done }, groups.reduce(0) { $0 + $1.progress.total })
        guard groups.count > 1, let focused = focused(in: groups) else { return String(localized: .noteCardsProgressNote(done, total)) }
        return String(localized: .noteCardsProgress(focused.progress.done, focused.progress.total, done, total))
    }

    func note(_ group: Group) -> String { String(localized: .noteCardsGroupProgress(group.progress.done, group.progress.total)) }

    // 절 묶음을 누르면 여는 노트의 그 절이다. 절을 찾지 못한 카드의 묶음은 노트의 처음을 연다.
    func link(to group: Group) -> AppLink { AppLink(.note, noteId, anchor: group.section.map { .heading($0) }) }

    func choose(_ group: Group) { focus = .some(group.section) }

    // MARK: A card

    func face(of card: StudyCard) -> Face { faces[card.id] ?? .front }

    func chip(_ record: CourseStudy.CardRecord) -> (text: String, tone: Tone)? { record.status.cardChip }

    func verdict(_ card: StudyCard) -> (text: String, tone: Tone)? {
        guard case .answered(let known, _) = face(of: card), let answer = card.answer else { return nil }
        let verdict: Verdict = known ? .correct : .wrong
        let said = String(localized: answer ? .solveTrue : .solveFalse)
        return (String(localized: .noteCardsVerdict(verdict.label, said)), verdict.tone)
    }

    func reveal(_ card: StudyCard) {
        guard card.kind == .flip, face(of: card) == .front else { return }
        faces[card.id] = .back
        focus = .some(section(of: card))
    }

    func mark(_ card: StudyCard, known: Bool) {
        guard card.kind == .flip, face(of: card) == .back,
            workspace.run(CardFlip(course: courseId, unit: card.unitId, card: card.id, known: known)) != nil
        else { return }
        faces[card.id] = .answered(known: known, picked: nil)
        focus = .some(section(of: card))
    }

    func pick(_ card: StudyCard, answer: Bool) {
        guard card.kind == .trueFalse, !face(of: card).isAnswered,
            workspace.run(CardFlip(course: courseId, unit: card.unitId, card: card.id, answer: answer)) != nil
        else { return }
        faces[card.id] = .answered(known: card.knows(picking: answer), picked: answer)
        focus = .some(section(of: card))
    }

    // 절을 찾지 못하는 카드는 노트 전체의 묶음에 있다.
    private func section(of card: StudyCard) -> String? {
        card.noteSection.flatMap { anchor in outline.contains { $0.anchor == anchor } ? anchor : nil }
    }

    // MARK: Adding

    // 카드는 단원의 파일에 두므로 노트에 이은 단원이 있어야 한다. 단원에 잇지 않은 노트는 과목의 첫 단원에 둔다.
    var unit: UUID? {
        guard let file = course?.file else { return nil }
        let linked = entry?.unitIds.first { id in file.units.contains { $0.id == id } }
        return linked ?? UnitTree.outline(file.units).first?.unit.id
    }

    func draft(in groups: [Group]) -> CardDraft? {
        guard let unit else { return nil }
        return CardDraft(unitId: unit, note: noteId, section: focused(in: groups)?.section)
    }
}
