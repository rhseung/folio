import FolioDomain
import Foundation
import Observation

/// 제안함 (#132): what the LMS brought in, by LMS classroom, waiting to be added or dismissed. No classroom is tied to a
/// course; each addition picks one. Nothing is written to a course until then.
@MainActor @Observable
final class ProposalsModel {
    let workspace: Workspace
    /// Proposals being added: a file downloads first, and its row waits.
    private(set) var adding: Set<String> = []

    init(workspace: Workspace) { self.workspace = workspace }

    var inbox: LMSInbox { workspace.lmsInbox }
    var sections: [LMSInbox.Section] { inbox.sections }

    /// The courses an item can go to: this term's, in the sidebar's order, or every course between terms.
    var targets: [(id: UUID, title: String)] {
        let current = workspace.currentCourses
        return (current.isEmpty ? workspace.courses : current).map { ($0.id, $0.title) }
    }

    var total: Int { inbox.proposals.count }

    /// The earliest deadline among the proposed assignments, since that is what can be missed.
    var earliestDue: String? {
        let first = inbox.proposals.compactMap { p -> (Date, String)? in
            if case .assignment(let a) = p.item, let due = a.due { return (due, a.title) }
            return nil
        }.min { $0.0 < $1.0 }
        return first.map { String(localized: .lmsTodayDetail(Self.time($0.0, now: workspace.now, calendar: workspace.calendar), $0.1)) }
    }

    var subtitle: String { String(localized: .lmsProposalsSubtitle) }

    var emptyDetail: String {
        switch workspace.lms.status {
        case .off: String(localized: .lmsNotConnected)
        case .needsLogin: String(localized: .lmsNeedsLogin)
        case .failed(let reason): reason
        case .syncing: String(localized: .lmsSyncing)
        case .idle: lastSync
        }
    }

    var lastSync: String {
        guard let at = workspace.lms.snapshot?.at, at > .distantPast else { return String(localized: .lmsNeverSynced) }
        return String(localized: .lmsLastSync(Self.time(at, now: workspace.now, calendar: workspace.calendar)))
    }

    func canAdd(_ p: LMSProposal) -> Bool {
        switch p.item {
        case .assignment: true
        case .file(let f): !workspace.lms.viewerOnly.contains(f.id)
        case .notice: false
        }
    }

    func isViewerOnly(_ p: LMSProposal) -> Bool {
        if case .file(let f) = p.item { return workspace.lms.viewerOnly.contains(f.id) }
        return false
    }

    /// What a row is: a deadline, the name it gets in `Lectures`, a notice's date and author.
    func detail(_ p: LMSProposal) -> String {
        switch p.item {
        case .assignment(let a):
            let due = a.due.map { String(localized: .lmsDue(Self.time($0, now: workspace.now, calendar: workspace.calendar))) }
            return [String(localized: .lmsKindAssignment), due].compactMap { $0 }.joined(separator: " · ")
        case .file(let f):
            let place = "\(CourseFolder.lectures.rawValue)/\(f.lectureName(f.title))"
            return [String(localized: .lmsKindFile), isViewerOnly(p) ? nil : place].compactMap { $0 }.joined(separator: " · ")
        case .notice(let n):
            let day = n.posted.map { $0.formatted(.dateTime.month().day()) }
            return [String(localized: .lmsKindNotice), day, n.author].compactMap { $0 }.joined(separator: " · ")
        }
    }

    func symbol(_ p: LMSProposal) -> String {
        switch p.item {
        case .assignment: "checklist"
        case .file: "doc.text"
        case .notice: "text.bubble"
        }
    }

    func addable(_ section: LMSInbox.Section) -> [LMSProposal] { section.proposals.filter(canAdd) }

    func isAdding(_ proposals: [LMSProposal]) -> Bool { !adding.isDisjoint(with: proposals.map(\.id)) }

    func add(_ proposals: [LMSProposal], into course: UUID) async {
        let ids = Set(proposals.map(\.id))
        adding.formUnion(ids)
        defer { adding.subtract(ids) }
        await workspace.accept(proposals.filter(canAdd), into: course)
    }

    func dismiss(_ proposals: [LMSProposal]) { workspace.dismiss(proposals) }

    /// Today and this year leave out what they repeat: "오후 2:40", "11월 20일 (금) 23:59".
    static func time(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day: Date.FormatStyle = sameYear ? .dateTime.month().day().weekday(.abbreviated) : .dateTime.year().month().day().weekday(.abbreviated)
        return date.formatted(day.hour().minute())
    }
}
