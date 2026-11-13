import FolioDomain
import FolioStorage
import Foundation
import Observation

/// The first run (#453, 안 B): 소개, 자료 폴더, then four steps that can wait for settings. With a remembered folder
/// that can't be opened it is the folder step alone, to connect it again (`trouble`).
@MainActor @Observable
final class FirstRunModel {
    let workspace: Workspace
    var step: FirstRunStep
    var start = FolderStart.existing
    /// The folder picked on the folder step, opened only when the step is left with 계속.
    private(set) var picked: Picked?
    /// Holds the day boundary and the API key, saved through the same paths as settings.
    let settings: SettingsModel
    /// The semester the term step lists courses of; nil follows the workspace's current one.
    var chosenSemester: UUID?
    private(set) var permissions: [SystemPermission: SystemPermission.State] = [:]
    /// The picked folder is still coming down from iCloud: the folder step shows its download in place of the choice.
    private(set) var waiting = false
    /// Started to connect a lost folder again. Kept apart from `trouble`, which clears once a folder it waited for opens.
    private var reconnecting = false
    #if DEBUG
    /// Shown in place of the workspace's own trouble by the debug walk (`FirstRunDebug`), which has a folder open.
    /// Nothing is picked yet then, as when the remembered folder is really gone.
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
        /// nil where the folder couldn't be read.
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
        // A lost folder is the folder step alone, whatever step was asked for.
        if trouble != nil {
            self.step = .folder
            reconnecting = true
        }
    }

    // MARK: Steps

    /// The remembered folder that couldn't be opened, while none is: the run is then only about that folder.
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

    /// Reconnecting a lost folder can't be put off, so it offers no 나중에 and marks nothing optional.
    var offersLater: Bool { step.isOptional && trouble == nil }

    func marksOptional(_ step: FirstRunStep) -> Bool { step.isOptional && trouble == nil && !isDone(step) }

    var primaryTitle: LocalizedStringResource {
        trouble != nil ? .commonOpen : isLast ? .firstRunStart : .firstRunContinue
    }

    /// 계속 (시작 on the last step, 열기 when connecting a folder again).
    func proceed() {
        if step == .folder {
            guard canContinue, let picked else { return }
            if picked.url != workspace.gist?.url {
                guard workspace.openWhenHere(picked.url) else { waiting = true; return }
                settings.load()
            }
            waiting = false
            // A lost folder reconnected is the whole job; an empty one picked instead still needs its term.
            if reconnecting {
                reconnecting = false
                if start == .existing { return finish() }
                workspace.showsFirstRun = true
            }
        }
        if step == .claude, !settings.apiKey.isEmpty { settings.saveKey() }
        advance()
    }

    /// 나중에: the step is left as it is, to be done in settings.
    func later() {
        guard step.isOptional else { return }
        advance()
    }

    private func advance() {
        guard let next = step.next else { return finish() }
        step = next
        entered()
    }

    /// Nothing is saved here: each step saves as it changes, and the settings copy may predate the folder now open.
    func finish() {
        workspace.finishFirstRun()
    }

    /// The folder is open by the term step: its settings are read again from it, or the day boundary would show and
    /// save the defaults the model started with.
    private func entered() {
        if step == .term { settings.load() }
    }

    // MARK: Folder

    /// Picks how to start; true when the folder picker should open, as no usable folder is picked yet.
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
        // The folder says what it is: a GIST folder picked from 새로 시작 opens as one rather than being refused.
        if let fits = kind?.start { start = fits }
    }

    var pickedPath: String? { picked.map { Self.shown($0.url) } }

    var pickedProblem: String? {
        guard let picked else { return nil }
        guard let kind = picked.kind else { return String(localized: .firstRunUnreadable) }
        return kind.problem(for: start).map(Self.message)
    }

    /// 학기 n개, 과목 n개, or 빈 폴더: what the picked folder holds, under its path.
    var pickedSummary: [String] {
        switch picked?.kind {
        case .gist(let semesters, let courses)?: [String(localized: .firstRunSemesterCount(semesters)), String(localized: .firstRunCourseCount(courses))]
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
