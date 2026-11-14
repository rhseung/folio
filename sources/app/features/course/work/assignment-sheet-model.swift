import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class AssignmentSheetModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    let assignment: Assignment
    var pending: PendingAction?
    var title = ""
    var hasDue = false
    var due = Date.now
    var status: AssignmentStatus = .todo
    var repeats: AssignmentRepeat?
    var customRepeat = false
    private(set) var target = ScoreTarget.none
    var scores: [UUID: String] = [:]
    var maxes: [UUID: String] = [:]
    var memo = ""

    init(workspace: Workspace, course: LoadedCourse, assignment: Assignment) {
        self.workspace = workspace
        initial = course
        self.assignment = assignment
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var files: [FolioDomain.Material] { AssignmentFiles.materials(of: assignment, in: course.file.materials) }
    var folder: String { AssignmentFiles.path(of: assignment) }
    var sheetTitle: String { String(localized: .commonEditNamed(assignment.title)) }

    var invalid: Bool {
        targetComponents.contains { c in
            !(scores[c.id] ?? "").isEmpty && (Double(scores[c.id] ?? "") == nil || (Double(maxes[c.id] ?? "") ?? 0) <= 0)
        }
    }

    var titleDetail: String? {
        let renamed = AssignmentFiles.path(of: Assignment(device: workspace.device, at: .now, title: title))
        return renamed == folder || files.isEmpty ? nil : String(localized: .assignmentsRenamedFolder(renamed))
    }

    var repeatDetail: String? {
        guard let repeats else { return nil }
        guard hasDue else { return String(localized: .assignmentsRepeatNeedsDue) }
        let next = course.file.nextDue(after: due, rule: repeats, title: assignment.title, calendar: workspace.calendar)
        return String(localized: .assignmentsRepeatNext(CourseFile.deadline(next, calendar: workspace.calendar)))
    }

    var repeatLabel: String { repeats?.label ?? String(localized: .repeatPickerNone) }

    var dueWeekday: Int? { hasDue ? workspace.calendar.isoWeekday(of: due) : nil }

    func pickRepeat(_ rule: AssignmentRepeat?) {
        repeats = rule
        customRepeat = false
    }

    func customizeRepeat() {
        if repeats == nil { repeats = .weekly }
        customRepeat = true
    }

    var customRule: AssignmentRepeat {
        get { repeats ?? .weekly }
        set { repeats = newValue }
    }

    var sortedComponents: [GradeComponent] { course.file.components.sorted { $0.order < $1.order } }

    var targetComponents: [GradeComponent] {
        switch target {
        case .none: []
        case .component(let id): sortedComponents.filter { $0.id == id }
        case .group(let g): sortedComponents.filter { $0.group == g }
        }
    }

    var targetOptions: [PickOption<ScoreTarget>] {
        var options = [PickOption(id: ScoreTarget.none, title: String(localized: .assignmentsNoTarget))]
        var seen = Set<String>()
        for c in sortedComponents {
            guard let g = c.group else { options.append(PickOption(id: .component(c.id), title: c.name)); continue }
            guard seen.insert(g).inserted else { continue }
            let members = sortedComponents.filter { $0.group == g }
            options.append(
                PickOption(
                    id: .group(g), title: String(localized: .assignmentsWholeGroup(g)),
                    detail: String(localized: .assignmentsWholeGroupDetail(members.count))))
            options += members.map { PickOption(id: .component($0.id), title: $0.name, depth: 1) }
        }
        return options
    }

    func pick(_ t: ScoreTarget) {
        target = t
        for c in targetComponents where (maxes[c.id] ?? "").isEmpty {
            maxes[c.id] = course.file.scores.last { $0.componentId == c.id }?.max.formatted()
        }
    }

    func load() {
        title = assignment.title
        hasDue = assignment.due != nil
        due = assignment.due ?? workspace.calendar.date(bySettingHour: 23, minute: 59, second: 0, of: workspace.now) ?? workspace.now
        status = assignment.status
        repeats = assignment.repeats
        customRepeat = repeats.map { !AssignmentRepeat.presets.contains($0) } ?? false
        memo = assignment.memo
        let own = course.file.scores.filter { $0.assignmentId == assignment.id }
        for s in own {
            scores[s.componentId] = s.score.formatted()
            maxes[s.componentId] = s.max.formatted()
        }
        target =
            assignment.componentGroup.map { .group($0) } ?? (assignment.componentId ?? own.first?.componentId).map { .component($0) }
            ?? .none
        loaded = draft
    }

    private struct Draft: Equatable {
        var title: String, hasDue: Bool, due: Date, status: AssignmentStatus, repeats: AssignmentRepeat?
        var target: ScoreTarget, scores: [UUID: String], maxes: [UUID: String], memo: String
    }

    private var draft: Draft {
        Draft(
            title: title, hasDue: hasDue, due: due, status: status, repeats: repeats, target: target, scores: scores, maxes: maxes,
            memo: memo)
    }

    private var loaded: Draft?

    var edited: Bool { loaded.map { $0 != draft } ?? false }

    enum Opening: Equatable {
        case elsewhere(URL)
        case materials(UUID)
        case window(UUID)
        case asks
    }

    var opening: FolioDomain.Material?

    // iPadOS에는 폴더를 열 곳이 없다.
    func opens(_ m: FolioDomain.Material) -> Bool {
        #if os(macOS)
        true
        #else
        !m.isFolder
        #endif
    }

    func open(_ m: FolioDomain.Material, windows: Bool) -> Opening {
        guard !m.isFolder else { return .elsewhere(course.store.fileURL(m.path)) }
        guard edited else { return .materials(m.id) }
        if windows { return .window(m.id) }
        opening = m
        return .asks
    }

    func saveAndOpen() -> Bool {
        opening = nil
        return apply()
    }

    func discardAndOpen() { opening = nil }

    func importFiles(_ urls: [URL]) { workspace.importFiles(urls, into: folder, course: course.id) }

    let kindOptions: [(MaterialKind, String)] = [
        (.problem, String(localized: .assignmentsProblem)),
        (.submission, String(localized: .assignmentsSubmission)),
        (.solution, String(localized: .assignmentsSolution)),
    ]

    func kind(of m: FolioDomain.Material) -> MaterialKind {
        m.kind ?? AssignmentFiles.guessKind(fileName: (m.path as NSString).lastPathComponent)
    }

    // 파일은 시트와 상관없이 이미 폴더에 있으므로, 확인할 때가 아니라 바로 저장한다.
    func setKind(_ m: FolioDomain.Material, _ kind: MaterialKind) {
        pending = workspace.ask(MaterialKindSet(course: course.id, kind: kind, materials: [m.id]))
    }

    func apply() -> Bool {
        let scored = targetComponents
        let entered = scored.compactMap { c -> AssignmentSave.Score? in
            guard let s = Double(scores[c.id] ?? ""), let m = Double(maxes[c.id] ?? ""), m > 0 else { return nil }
            return AssignmentSave.Score(component: c.id, score: s, max: m)
        }
        var componentId: UUID?, group: String?
        if case .component(let id) = target { componentId = id }
        if case .group(let g) = target { group = g }
        return workspace.run(
            AssignmentSave(
                course: course.id, assignment: assignment.id, title: .set(title), due: .set(hasDue ? due : nil),
                status: .set(status), repeats: .set(repeats), componentId: .set(componentId),
                componentGroup: .set(group), memo: .set(memo), scores: .set(entered))) != nil
    }

    func delete(then done: @escaping @MainActor () -> Void) {
        pending = workspace.ask(AssignmentRemove(course: course.id, assignment: assignment.id)) { _ in done() }
    }
}
