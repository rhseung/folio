import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class LMSModel {
    let workspace: Workspace
    private(set) var page: AppLink.LMSPage?
    private(set) var adding: Set<String> = []
    var showingHidden = false
    var pending: PendingAction?

    init(workspace: Workspace) { self.workspace = workspace }

    func follow(_ link: AppLink) {
        guard link.kind == .lms else { return }
        page = link.lmsPage
    }

    var board: ProposalBoard { workspace.proposalBoard }
    var isConnected: Bool { workspace.lms.isConnected }

    enum Shown {
        case all([ProposalBoard.Group])
        case room(ProposalBoard.Room)
        case thread(ProposalBoard.Thread)
        // 처리해서 비었거나 다른 기기에서 지운 강의실과 대화다.
        case gone
    }

    func shown(in board: ProposalBoard) -> Shown {
        switch page {
        case nil: .all(board.groups)
        case .classroom(let id): board.room(id).map(Shown.room) ?? .gone
        case .claude(let id): board.thread(id).map(Shown.thread) ?? .gone
        }
    }

    func title(of shown: Shown) -> String {
        switch shown {
        case .all, .gone: String(localized: .rootNavLms)
        case .room(let r): r.classroom.title
        case .thread(let t): t.title
        }
    }

    func subtitle(of shown: Shown) -> String? {
        switch shown {
        case .all: [String(localized: .lmsSubtitle), isConnected ? workspace.lmsLastSync : nil].compactMap { $0 }.joined(separator: " ")
        case .room(let r): r.classroom.professors
        case .thread(let t): courseTitle(t.course)
        case .gone: nil
        }
    }

    var emptyDetail: String {
        switch workspace.lms.status {
        case .off: String(localized: .lmsNotConnected)
        case .needsLogin: String(localized: .lmsNeedsLogin)
        case .failed(let reason): reason
        case .syncing: String(localized: .lmsSyncing)
        case .idle: workspace.lmsLastSync
        }
    }

    func count(_ proposals: [Proposal]) -> String? { proposals.isEmpty ? nil : "\(proposals.count)" }

    var targets: [(id: UUID, title: String)] {
        let current = workspace.currentCourses
        return (current.isEmpty ? workspace.courses : current).map { ($0.id, $0.title) }
    }

    func courseTitle(_ id: UUID) -> String? { workspace.course(id)?.title }

    // MARK: Rows

    // Claude 제안의 이름과 막힌 이유는 지금 폴더로 미리 실행해 얻는다. 화면을 다시 그릴 때마다 돌리지 않도록 폴더가 바뀔
    // 때까지 기억한다.
    @ObservationIgnored private var lines: [ActionProposal: (title: String, refusal: String?)] = [:]
    @ObservationIgnored private var linesKey: [Int] = []

    private func line(_ c: ChatProposal) -> (title: String, refusal: String?) {
        let key = [workspace.dataRevision, workspace.chatsRevision]
        if linesKey != key {
            lines = [:]
            linesKey = key
        }
        if let line = lines[c.proposal] { return line }
        let line: (String, String?)
        if let action = Actions.action(c.proposal) {
            line = (workspace.summary(action), workspace.waiting(c)?.reason ?? workspace.refusal(action) ?? c.proposal.failure)
        } else {
            line = (c.proposal.command, String(localized: .claudeProposalUnknown))
        }
        lines[c.proposal] = line
        return line
    }

    func title(_ p: Proposal) -> String {
        if case .claude(let c) = p.source { return line(c).title }
        return p.title ?? ""
    }

    func reason(_ p: Proposal) -> String? {
        if case .claude(let c) = p.source { return line(c).refusal }
        return nil
    }

    // 전체에서는 제안이 어디서 왔는지(강의실, 대화)를 앞에 붙인다.
    func detail(_ p: Proposal, source: Bool) -> String? {
        let parts: [String?]
        switch p.source {
        case .lms(let item):
            parts = [source ? item.classroom.title : nil] + lmsDetail(item, viewerOnly: p.flag == .viewerOnly)
        case .claude(let c):
            parts = source ? [c.chatTitle, courseTitle(c.course)] : []
        case .cleanup(let m):
            parts = [m.to]
        }
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    private func lmsDetail(_ p: LMSProposal, viewerOnly: Bool) -> [String?] {
        switch p.item {
        case .assignment:
            let files = LMSAttachment.summary(p.attachments).map {
                $0.more == 0 ? $0.first : String(localized: .lmsAttachmentsMore($0.first, $0.more))
            }
            return [String(localized: .lmsKindAssignment), files]
        case .file(let f):
            return [String(localized: .lmsKindFile), viewerOnly ? nil : "\(CourseFolder.lectures.rawValue)/\(f.lectureName(f.title))"]
        case .notice(let n):
            return [String(localized: .lmsKindNotice), n.posted.map { $0.formatted(.dateTime.month().day()) }, n.author]
        }
    }

    func due(_ p: Proposal) -> (text: String, urgency: DueUrgency)? {
        guard let due = p.due else { return nil }
        let days = workspace.settings.studyDays(from: workspace.now, until: due, calendar: workspace.calendar)
        let urgency = workspace.settings.urgency
        return (DueUrgency.text(due, studyDays: days, settings: urgency), DueUrgency(studyDays: days, settings: urgency))
    }

    // 받을 수 없는 항목(공지, 뷰어 전용 자료)과 과제는 LMS에서 열어 본다.
    func showsOpen(_ p: Proposal) -> Bool { p.url != nil && (!p.canApprove || p.kind == .lmsAssignment) }

    // MARK: Actions

    func addable(_ proposals: [Proposal]) -> [Proposal] { proposals.filter { $0.kind.picksCourse && $0.canApprove } }

    func isAdding(_ proposals: [Proposal]) -> Bool { !adding.isDisjoint(with: proposals.map(\.id)) }

    func add(_ proposals: [Proposal], into course: UUID) async {
        let ids = Set(proposals.map(\.id))
        adding.formUnion(ids)
        defer { adding.subtract(ids) }
        await workspace.approve(proposals, into: course)
    }

    func apply(_ p: Proposal) {
        guard case .claude(let c) = p.source else { return }
        pending = workspace.ask(c)
    }

    func dismiss(_ proposals: [Proposal]) { workspace.dismiss(proposals) }

    func proposeAgain(_ h: LMSInbox.Handled) { workspace.propose(again: [h]) }

    func detail(_ h: LMSInbox.Handled) -> String {
        let base = lmsDetail(h.proposal, viewerOnly: false).compactMap { $0 }.joined(separator: " · ")
        guard let id = h.course, let title = courseTitle(id) else { return base }
        return [base, String(localized: .lmsAddedTo(title))].joined(separator: " · ")
    }

    // MARK: Today

    var earliestDue: String? {
        let first = board.proposals.compactMap { p -> (Date, String)? in p.due.map { ($0, title(p)) } }.min { $0.0 < $1.0 }
        return first.map { String(localized: .lmsTodayDetail(workspace.lmsTime($0.0), $0.1)) }
    }

    // 오늘 화면은 처리할 것이 있는 강의실과 대화만 수와 함께 보인다.
    var todayRows: [TodayRow] {
        let board = board
        return board.rooms.filter { !$0.proposals.isEmpty }.map {
            TodayRow(id: "room/\($0.id)", title: $0.classroom.title, count: $0.proposals.count)
        }
            + board.threads.map { TodayRow(id: "chat/\($0.id)", title: $0.title, count: $0.proposals.count) }
    }

    struct TodayRow: Identifiable {
        var id: String
        var title: String
        var count: Int
    }
}
