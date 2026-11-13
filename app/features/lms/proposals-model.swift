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
    /// Classrooms whose handled items are shown. Folded by default: the first sync alone marks a term's worth of posts.
    var showingHandled: Set<Int> = []

    init(workspace: Workspace) { self.workspace = workspace }

    var inbox: LMSInbox { workspace.lmsInbox }
    var sections: [LMSInbox.Section] { inbox.sections }
    var waiting: [LMSInbox.Section] { inbox.waiting }

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
        return first.map { String(localized: .lmsTodayDetail(workspace.lmsTime($0.0), $0.1)) }
    }

    var subtitle: String { String(localized: .lmsProposalsSubtitle) }

    var emptyDetail: String {
        switch workspace.lms.status {
        case .off: String(localized: .lmsNotConnected)
        case .needsLogin: String(localized: .lmsNeedsLogin)
        case .failed(let reason): reason
        case .syncing: String(localized: .lmsSyncing)
        case .idle: workspace.lmsLastSync
        }
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

    /// An assignment's deadline as Today's list shows it, with how near it is. The chip carries it, not the detail line.
    func due(_ p: LMSProposal) -> (text: String, urgency: DueUrgency)? {
        guard case .assignment(let a) = p.item, let due = a.due else { return nil }
        let calendar = workspace.calendar
        let days = workspace.settings.studyDays(from: workspace.now, until: due, calendar: calendar)
        return (TodayModel.dueText(due, studyDays: days), DueUrgency(studyDays: days))
    }

    /// What a row is: the name it gets in `Lectures`, a notice's date and author.
    func detail(_ p: LMSProposal) -> String {
        switch p.item {
        case .assignment:
            return String(localized: .lmsKindAssignment)
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

    /// A classroom left with only hidden items counts for nothing, so its header shows no number.
    func count(_ section: LMSInbox.Section) -> String? { section.proposals.isEmpty ? nil : "\(section.proposals.count)" }

    func isLast(_ p: LMSProposal, in section: LMSInbox.Section) -> Bool { section.handled.isEmpty && p.id == section.proposals.last?.id }

    /// A file that can be added says enough in its row; an assignment's page has the submission details the row leaves out.
    func showsOpen(_ p: LMSProposal) -> Bool { !canAdd(p) || p.key.kind == .assignment }

    func isAdding(_ proposals: [LMSProposal]) -> Bool { !adding.isDisjoint(with: proposals.map(\.id)) }

    func add(_ proposals: [LMSProposal], into course: UUID) async {
        let ids = Set(proposals.map(\.id))
        adding.formUnion(ids)
        defer { adding.subtract(ids) }
        await workspace.accept(proposals.filter(canAdd), into: course)
    }

    func dismiss(_ proposals: [LMSProposal]) { workspace.dismiss(proposals) }

    func showsHandled(_ section: LMSInbox.Section) -> Bool { showingHandled.contains(section.id) }

    func toggleHandled(_ section: LMSInbox.Section) {
        if showingHandled.contains(section.id) { showingHandled.remove(section.id) } else { showingHandled.insert(section.id) }
    }

    func canProposeAgain(_ h: LMSInbox.Handled) -> Bool { h.proposable }

    func proposeAgain(_ h: LMSInbox.Handled) { workspace.propose(again: [h.proposal]) }

    func detail(_ h: LMSInbox.Handled) -> String {
        guard let id = h.course, let course = workspace.courses.first(where: { $0.id == id }) else { return detail(h.proposal) }
        return [detail(h.proposal), String(localized: .lmsAddedTo(course.title))].joined(separator: " · ")
    }
}
