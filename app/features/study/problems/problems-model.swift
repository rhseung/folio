import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class ProblemsModel {
    struct Group: Identifiable {
        var set: ProblemSet
        var note: String
        var records: [CourseStudy.ProblemRecord]
        var items: [Item]
        var id: UUID { self.set.id }
    }

    // 묶음의 나무를 그릴 칸이다. 지문은 편 동안 그 소문제(`children`)를 담은 상자이고, 접으면 칸 하나다(`children`이 nil).
    // 모두 한 흐름에 놓여서 상자가 작으면 번호 칸 사이에 끼고, 크면 다음 줄로 넘어가 접힌다.
    indirect enum Item: Identifiable {
        case cell(CourseStudy.ProblemRecord)
        case stem(ProblemGroup, note: String, children: [Item]?)

        var id: UUID {
            switch self {
            case .cell(let r): r.problem.id
            case .stem(let g, _, _): g.id
            }
        }
    }

    // 문제 뽑기 하나의 알림 카드다. 뽑는 중, 실패, 받을 초안을 자료마다 하나씩 보인다.
    struct Extraction: Identifiable, Equatable {
        var material: UUID
        var title: String
        var detail: String?
        var phase: ExtractionPhase
        var id: UUID { material }
    }

    enum ExtractionPhase: Equatable {
        case working
        case failed
        case ready
    }

    let workspace: Workspace
    let courseId: UUID
    var filter = SolvePick.Filter.all
    var unit: UUID?
    var collapsed: Set<UUID> = []
    // 초안은 `.folio/drafts`의 파일이라, 그릴 때마다 읽지 않고 `studyRevision`이 바뀔 때만 다시 읽는다.
    @ObservationIgnored private var draftCache: (revision: Int, drafts: [StudyDraft])?

    init(workspace: Workspace, courseId: UUID) {
        self.workspace = workspace
        self.courseId = courseId
    }

    var study: CourseStudy? { workspace.study(of: courseId) }

    var subtitle: String {
        guard let study else { return "" }
        let all = study.allProblems
        return [
            String(localized: .problemsSetCount(study.file.problemSets.count)), String(localized: .problemsCount(all.count)),
            String(localized: .problemsWrongCount(all.filter(\.status.isOpen).count)),
            String(localized: .problemsRecheckCount(all.filter(\.status.isRecheck).count)),
        ].joined(separator: " · ")
    }

    var filterOptions: [(SolvePick.Filter, String)] {
        [
            (.all, String(localized: .solveFilterAll)), (.wrong, String(localized: .solveFilterWrong)),
            (.untried, String(localized: .solveFilterUntried)),
        ]
    }

    var unitOptions: [SelectOption<UUID?>] {
        [SelectOption(id: UUID?.none, label: String(localized: .solveAllUnits))]
            + UnitTree.outline(study?.file.units ?? []).map {
                SelectOption(id: Optional($0.unit.id), label: $0.unit.title, depth: $0.depth)
            }
    }

    private var pick: SolvePick { SolvePick(filter: filter, units: unit.map { [$0] } ?? []) }

    // 거르면 맞는 문제가 없는 묶음은 숨긴다. 거르지 않으면 문제가 없는 묶음도 보여 문제를 넣을 수 있게 한다.
    var groups: [Group] {
        guard let study else { return [] }
        let pick = pick, filtered = filter != .all || unit != nil
        return study.file.problemSets.compactMap { set in
            let records = study.problems(inSet: set.id).filter(pick.matches)
            if filtered, records.isEmpty { return nil }
            let solved = records.filter(\.solved).count
            return Group(
                set: set, note: [set.source.label, String(localized: .problemsSolvedOf(solved, records.count))].joined(separator: " · "),
                records: records,
                items: items(
                    ProblemTree(set).roots, shown: Dictionary(records.map { ($0.problem.id, $0) }, uniquingKeysWith: { a, _ in a })))
        }
    }

    // 거른 문제가 하나도 없는 지문은 숨긴다. 문제 아래에 매달린 소문제(3 아래 3a)는 같은 흐름의 칸으로 잇는다.
    private func items(_ nodes: [ProblemTree.Node], shown: [UUID: CourseStudy.ProblemRecord]) -> [Item] {
        nodes.flatMap { n -> [Item] in
            guard let g = n.group else { return n.questions.compactMap { shown[$0.id] }.map(Item.cell) }
            let inside = n.questions.compactMap { shown[$0.id] }
            guard !inside.isEmpty else { return [] }
            let note = String(localized: .problemsSolvedOf(inside.filter(\.solved).count, inside.count))
            return [.stem(g, note: note, children: collapsed.contains(g.id) ? nil : items(n.children, shown: shown))]
        }
    }

    func toggleCollapsed(_ id: UUID) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    var isEmpty: Bool { study?.file.problemSets.isEmpty ?? true }

    // 다른 기기가 받은 초안은 그 기기가 지우기 전까지 남아 있으므로, 과목 문서에 남은 제안 ID로 거른다.
    private var drafts: [StudyDraft] {
        let revision = workspace.studyRevision
        if let cache = draftCache, cache.revision == revision { return cache.drafts }
        guard let course = workspace.course(courseId) else { return [] }
        let found = ((try? course.store.drafts()) ?? []).map(\.model).filter { d in
            d.kind == .problems && !d.isApplied && !(d.proposal.id.map(course.file.hasApplied) ?? false)
        }
        draftCache = (revision, found)
        return found
    }

    var extractions: [Extraction] {
        guard let file = workspace.course(courseId)?.file else { return [] }
        func name(_ id: UUID?) -> String? {
            file.materials.first { $0.id == id }.map { ($0.path as NSString).lastPathComponent }
        }
        let states = workspace.extractor.states
        var out: [Extraction] = states.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { id in
            guard let file = name(id), let state = states[id] else { return nil }
            switch state {
            case .waiting: return Extraction(material: id, title: String(localized: .problemExtractWaiting(file)), phase: .working)
            case .running: return Extraction(material: id, title: String(localized: .problemExtractRunning(file)), phase: .working)
            case .failed(let why):
                return Extraction(material: id, title: String(localized: .problemExtractFailed(file)), detail: why, phase: .failed)
            }
        }
        for d in drafts {
            guard let id = d.materialId, states[id] == nil, let file = name(id) else { continue }
            out.append(
                Extraction(
                    material: id, title: String(localized: .problemExtractReady(file, d.problems.count)), detail: summary(of: d),
                    phase: .ready))
        }
        return out
    }

    private func summary(of draft: StudyDraft) -> String {
        let numbers = draft.problems.map(\.number)
        let span =
            switch (numbers.first, numbers.last) {
            case (let first?, let last?) where first != last: String(localized: .problemExtractNumbers(first, last))
            case (let first?, _): String(localized: .problemExtractNumber(first))
            default: nil as String?
            }
        let units = Set(draft.problems.flatMap(\.unitIds)).count
        let solution = draft.solutionMaterialId.flatMap { id in
            workspace.course(courseId)?.file.materials.first { $0.id == id }.map { ($0.path as NSString).lastPathComponent }
        }
        return [
            span, units > 0 ? String(localized: .problemExtractUnits(units)) : String(localized: .problemExtractNoUnits),
            solution.map { String(localized: .problemExtractSolution($0)) },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    var sheetOptions: [SelectOption<UUID>] {
        guard let file = workspace.course(courseId)?.file else { return [] }
        return ProblemExtraction.sheets(in: file, kinds: workspace.settings.assignmentKindTable).map { m in
            SelectOption(
                id: m.id, label: (m.path as NSString).lastPathComponent, detail: (m.path as NSString).deletingLastPathComponent,
                isFile: true)
        }
    }

    func extract(_ material: UUID) { workspace.extractProblems(from: material, in: courseId) }

    func acceptAll(_ e: Extraction) { workspace.run(ProblemSetAccept(course: courseId, material: e.material)) }

    func retry(_ e: Extraction) { workspace.extractProblems(from: e.material, in: courseId) }

    func dismiss(_ e: Extraction) { workspace.extractor.clear(e.material) }

    func tone(_ r: CourseStudy.ProblemRecord) -> Tone {
        switch r.status {
        case .open: .danger
        case .recheck: .warning
        case .resolved, .neverWrong: .success
        case .untried: .plain
        }
    }

    func help(_ r: CourseStudy.ProblemRecord) -> String {
        let units = r.problem.unitIds.compactMap { id in study?.file.units.first { $0.id == id }?.title }
        let status = r.status.problemChip?.text ?? (r.solved ? Verdict.correct.label : String(localized: .problemsUntried))
        return ([status] + units).joined(separator: " · ")
    }

    func solveRequest(_ group: Group? = nil) -> SolveRequest {
        SolveRequest(course: courseId, units: unit.map { [$0] } ?? [], set: group?.set.id, mode: nil)
    }

    func solveRequest(_ r: CourseStudy.ProblemRecord) -> SolveRequest {
        SolveRequest(course: courseId, set: r.setId, problems: [r.problem.id])
    }
}
