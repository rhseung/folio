import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class ProblemDraftModel {
    struct Row: Identifiable {
        var problem: Problem
        var kept = true
        var id: UUID { problem.id }
    }

    let workspace: Workspace
    let course: LoadedCourse
    let material: UUID
    let draft: StudyDraft?
    var title: String
    var rows: [Row]
    let groups: [ProblemGroup]
    // 그림 칸을 잘라 올 문제지 PDF다.
    let sheet: URL?
    var pending: PendingAction?
    // 버리기를 확인한 뒤 시트를 닫는다.
    var finished = false

    init(workspace: Workspace, course: LoadedCourse, material: UUID) {
        self.workspace = workspace
        self.course = course
        self.material = material
        let draft = ((try? course.store.drafts()) ?? []).map(\.model).first {
            $0.kind == .problems && $0.materialId == material && !$0.isApplied
        }
        self.draft = draft
        if case .string(let t)? = draft?.proposal.input["title"] { title = t } else { title = draft?.title ?? "" }
        rows = (draft?.problems ?? []).map { Row(problem: $0) }
        groups = draft?.groups ?? []
        sheet = course.file.materials.first { $0.id == material && $0.isPDF }.map { course.store.fileURL($0.path) }
    }

    var sheetTitle: String { String(localized: .problemDraftTitle(draft?.title ?? "")) }
    private var kept: [Problem] { rows.filter(\.kept).map(\.problem) }
    var confirmTitle: String { String(localized: .problemDraftAccept(kept.count)) }
    var canAccept: Bool { !kept.isEmpty && !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var unitOptions: [SelectOption<UUID>] {
        UnitTree.outline(course.file.units).map { SelectOption(id: $0.unit.id, label: $0.unit.title, depth: $0.depth) }
    }

    func caption(_ p: Problem) -> String {
        ([p.format.label] + (p.page.map { [String(localized: .problemDraftPage($0))] } ?? [])).joined(separator: " · ")
    }

    // 문제지의 나무를 위에서부터 펼친 줄이다. 접은 지문 아래는 보이지 않는다.
    enum Line: Identifiable {
        case group(ProblemGroup, depth: Int, leaves: [UUID])
        case problem(UUID, depth: Int)

        var id: UUID {
            switch self {
            case .group(let g, _, _): g.id
            case .problem(let id, _): id
            }
        }
    }

    enum Check { case all, some, none }

    var collapsed: Set<UUID> = []

    var lines: [Line] {
        func walk(_ nodes: [ProblemTree.Node]) -> [Line] {
            nodes.flatMap { n -> [Line] in
                guard let g = n.group else { return [.problem(n.id, depth: n.depth)] + walk(n.children) }
                return [.group(g, depth: n.depth, leaves: n.questions.map(\.id))] + (collapsed.contains(g.id) ? [] : walk(n.children))
            }
        }
        return walk(ProblemTree(problems: rows.map(\.problem), groups: groups).roots)
    }

    func index(of id: UUID) -> Int? { rows.firstIndex { $0.id == id } }

    func check(_ leaves: [UUID]) -> Check {
        let kept = rows.filter { leaves.contains($0.id) && $0.kept }.count
        return kept == 0 ? .none : kept == leaves.count ? .all : .some
    }

    func groupCaption(_ leaves: [UUID]) -> String { String(localized: .problemsCount(leaves.count)) }

    // 지문의 표시는 그 아래 문제를 모두 받거나 모두 뺀다. 일부만 받은 지문을 누르면 모두 받는다.
    func toggle(group leaves: [UUID]) {
        let keep = check(leaves) != .all
        for i in rows.indices where leaves.contains(rows[i].id) { rows[i].kept = keep }
    }

    func toggleCollapsed(_ id: UUID) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    func toggle(_ id: UUID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].kept.toggle()
    }

    func accept() -> Bool {
        workspace.run(
            ProblemSetAccept(course: course.id, material: material, title: title.trimmingCharacters(in: .whitespaces), problems: kept))
            != nil
    }

    func discard() {
        pending = workspace.ask(ProblemSetDiscard(course: course.id, material: material)) { [weak self] _ in self?.finished = true }
    }
}
