import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class FirstRunModel {
    let workspace: Workspace
    var step: FirstRunStep
    var start = FolderStart.existing
    private(set) var picked: Picked?
    let settings: SettingsModel
    var chosenSemester: UUID?
    private(set) var permissions: [SystemPermission: SystemPermission.State] = [:]
    private(set) var waiting = false
    private var reconnecting = false
    #if DEBUG
    var debugTrouble: FolderTrouble? {
        didSet {
            guard debugTrouble != nil else { return }
            reconnecting = true
            picked = nil
            step = .folder
        }
    }
    #endif

    struct Picked: Equatable {
        let url: URL
        let kind: FolderKind?
    }

    init(workspace: Workspace, step: FirstRunStep = .welcome) {
        self.workspace = workspace
        self.step = step
        settings = SettingsModel(workspace: workspace, tab: .claude)
        if let url = workspace.gist?.url {
            picked = Picked(url: url, kind: try? FolderKind(FolderProbe.outline(of: url)))
            start = picked?.kind?.start ?? .existing
        }
        settings.load()
        if trouble != nil {
            self.step = .folder
            reconnecting = true
        }
    }

    // MARK: Steps

    var trouble: FolderTrouble? {
        #if DEBUG
        if let debugTrouble { return debugTrouble }
        #endif
        if waiting, let picked = workspace.folderTrouble { return picked }
        return workspace.gist == nil ? workspace.folderTrouble : nil
    }

    var steps: [FirstRunStep] { trouble == nil ? FirstRunStep.allCases : [.folder] }

    func isReachable(_ step: FirstRunStep) -> Bool { step.isReachable(folderOpen: workspace.gist != nil) }

    func go(to step: FirstRunStep) {
        guard isReachable(step), trouble == nil else { return }
        self.step = step
        entered()
    }

    var canGoBack: Bool { trouble == nil && step.previous != nil }

    func back() {
        guard let previous = step.previous else { return }
        step = previous
        entered()
    }

    var canContinue: Bool {
        switch step {
        case .folder: picked.map { $0.kind.map { $0.problem(for: start) == nil } ?? false } ?? false
        default: true
        }
    }

    var isLast: Bool { trouble == nil && step.next == nil }

    func isDone(_ step: FirstRunStep) -> Bool { trouble == nil && step < self.step }

    var offersLater: Bool { step.isOptional && trouble == nil }

    func marksOptional(_ step: FirstRunStep) -> Bool { step.isOptional && trouble == nil && !isDone(step) }

    var primaryTitle: LocalizedStringResource {
        trouble != nil ? .commonOpen : isLast ? .firstRunStart : .firstRunContinue
    }

    func proceed() {
        if step == .folder {
            guard canContinue, let picked else { return }
            if picked.url != workspace.gist?.url {
                guard workspace.openWhenHere(picked.url) else { waiting = true; return }
                settings.load()
            }
            waiting = false
            if reconnecting {
                reconnecting = false
                if start == .existing { return finish() }
                workspace.showsFirstRun = true
            }
        }
        if step == .claude, !settings.apiKey.isEmpty { settings.saveKey() }
        advance()
    }

    func later() {
        guard step.isOptional else { return }
        advance()
    }

    private func advance() {
        guard let next = step.next else { return finish() }
        step = next
        entered()
    }

    func finish() {
        workspace.finishFirstRun()
    }

    private func entered() {
        if step == .term { settings.load() }
    }

    // MARK: Folder

    func choose(_ start: FolderStart) -> Bool {
        self.start = start
        return picked == nil || pickedProblem != nil
    }

    func choose(_ url: URL) {
        if waiting {
            workspace.stopWaiting()
            waiting = false
        }
        _ = url.startAccessingSecurityScopedResource()
        let kind = try? FolderKind(FolderProbe.outline(of: url))
        picked = Picked(url: url, kind: kind)
        if let fits = kind?.start { start = fits }
    }

    var pickedPath: String? { picked.map { Self.shown($0.url) } }

    var pickedProblem: String? {
        guard let picked else { return nil }
        guard let kind = picked.kind else { return String(localized: .firstRunUnreadable) }
        return kind.problem(for: start).map(Self.message)
    }

    var pickedSummary: [String] {
        switch picked?.kind {
        case .gist(let semesters, let courses)?:
            [String(localized: .firstRunSemesterCount(semesters)), String(localized: .firstRunCourseCount(courses))]
        case .empty?: [String(localized: .firstRunEmptyFolder)]
        default: []
        }
    }

    static func message(_ problem: FolderChoiceProblem) -> String {
        switch problem {
        case .alreadyFolio: String(localized: .firstRunProblemAlreadyFolio)
        case .notEmpty: String(localized: .firstRunProblemNotEmpty)
        case .empty: String(localized: .firstRunProblemEmpty)
        case .notFolio: String(localized: .firstRunProblemNotFolio)
        }
    }

    static func shown(_ url: URL) -> String { (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath }

    func findAgain() {
        workspace.openRemembered()
    }

    // MARK: Term

    var semesters: [Semester] { workspace.semesters }

    var semester: Semester? {
        chosenSemester.flatMap { id in semesters.first { $0.id == id } } ?? workspace.currentSemester ?? semesters.first
    }

    func accent(_ id: UUID) -> CourseAccent { workspace.accent(id) }

    struct CourseLine: Identifiable {
        let id: UUID
        let title: String
        let days: String
    }

    var courses: [CourseLine] {
        guard let semester else { return [] }
        return workspace.courses(in: semester).map { c in
            let days = Set(c.file.course.schedule.map(\.weekday)).sorted().map { ClassTime.weekdayNames[$0 - 1] }
            return CourseLine(id: c.id, title: c.title, days: days.joined(separator: " "))
        }
    }

    func dayBoundaryChanged() { settings.saveNow() }

    // MARK: Permissions

    func state(of permission: SystemPermission) -> SystemPermission.State { permissions[permission] ?? .unknown }

    func refreshPermissions() async {
        for p in SystemPermission.allCases { permissions[p] = await p.state() }
    }

    func request(_ permission: SystemPermission) async {
        permissions[permission] = await permission.request()
    }
}
