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

    init(workspace: Workspace) { self.workspace = workspace }

    func follow(_ link: AppLink) {
        guard link.kind == .lms else { return }
        page = link.lmsPage
    }

    var board: ProposalBoard { workspace.proposalBoard }
    var isConnected: Bool { workspace.lms.isConnected }

    enum Shown {
        case all([Section])
        case room(ProposalBoard.Room)
        // 처리해서 비었거나 LMS에서 사라진 강의실이다.
        case gone
    }

    // "전체"와 강의실 페이지의 블록이다. 이번 주 기한은 제안이 아니라 보기만 하는 행이라 새 글 앞에 따로 선다.
    enum Section: Identifiable {
        case group(ProposalBoard.Group)
        case deadlines([LMSDeadline])

        var id: String {
            switch self {
            case .group(let g): g.group.rawValue
            case .deadlines: "deadlines"
            }
        }
    }

    func shown(in board: ProposalBoard) -> Shown {
        switch page {
        case nil: .all(Self.sections(board.groups, deadlines: board.deadlines))
        case .classroom(let id): board.room(id).map(Shown.room) ?? .gone
        }
    }

    func sections(of room: ProposalBoard.Room) -> [Section] {
        Self.sections(ProposalBoard(rooms: [room]).groups, deadlines: room.deadlines)
    }

    static func sections(_ groups: [ProposalBoard.Group], deadlines: [LMSDeadline]) -> [Section] {
        var out = groups.filter { $0.group != .posts }.map(Section.group)
        if !deadlines.isEmpty { out.append(.deadlines(deadlines)) }
        out += groups.filter { $0.group == .posts }.map(Section.group)
        return out
    }

    func title(of shown: Shown) -> String {
        switch shown {
        case .all, .gone: String(localized: .rootNavLms)
        case .room(let r): r.classroom.title
        }
    }

    func subtitle(of shown: Shown) -> String? {
        switch shown {
        case .all: nil
        case .room(let r): r.classroom.professors
        case .gone: nil
        }
    }

    // 열 아래에 두는 동기화 시각이다. 연결하지 않았으면 열의 연결 안내가 대신한다.
    var syncNote: String? {
        guard isConnected else { return nil }
        if case .syncing = workspace.lms.status { return String(localized: .lmsSyncing) }
        return workspace.lmsLastSync
    }

    var emptyDetail: String {
        switch workspace.lms.status {
        case .off: String(localized: .lmsNotConnected)
        case .needsLogin: String(localized: .lmsNeedsLogin)
        case .failed(let reason): reason
        case .offline: String(localized: .lmsOfflineDetail(workspace.lmsLastSync))
        case .syncing: String(localized: .lmsSyncing)
        case .idle: workspace.lmsLastSync
        }
    }

    // 머리의 칩이다. 동기화 중이거나 오프라인이면 마지막으로 읽은 내용(기기 캐시)을 보이는 중이라고 알린다.
    var statusChip: (text: String, tone: Tone)? {
        switch workspace.lms.status {
        case .syncing: (String(localized: .lmsSyncing), .plain)
        case .offline: (String(localized: .lmsOffline), .warning)
        case .off, .idle, .needsLogin, .failed: nil
        }
    }

    var needsLogin: Bool { workspace.lms.status == .needsLogin }

    func count(_ proposals: [Proposal]) -> String? { proposals.isEmpty ? nil : "\(proposals.count)" }

    var targets: [(id: UUID, title: String)] {
        let current = workspace.currentCourses
        return (current.isEmpty ? workspace.courses : current).map { ($0.id, $0.title) }
    }

    func courseTitle(_ id: UUID) -> String? { workspace.course(id)?.title }

    // MARK: Course memory

    // 받을 때 미리 고르는 과목이다. 기억한 과목이 지워졌으면 고르지 않는다.
    func remembered(_ classroom: Int) -> (id: UUID, title: String)? {
        guard let id = workspace.settings.lms.course(of: classroom), let title = courseTitle(id) else { return nil }
        return (id, title)
    }

    func remembered(_ p: Proposal) -> (id: UUID, title: String)? {
        guard case .lms(let item) = p.source else { return nil }
        return remembered(item.classroom.id)
    }

    func memoryLabel(_ room: ProposalBoard.Room) -> String {
        guard let memory = room.memory else { return String(localized: .lmsRoomCourse) }
        return memory.course.flatMap(courseTitle) ?? String(localized: .lmsNoCourse)
    }

    func remember(_ classroom: Int, course: UUID) { workspace.run(LMSRoomSet(classroom: classroom, course: course)) }
    func rememberNoCourse(_ classroom: Int) { workspace.run(LMSRoomSet(classroom: classroom, course: nil, none: true)) }
    func forget(_ classroom: Int) { workspace.run(LMSRoomSet(classroom: classroom, course: nil, forget: true)) }

    // 기억한 과목에 모두 받기는 새 항목만 받는다. 고칠 것(Folio와 다른 것)은 하나씩 처리한다.
    var remembered: [Proposal] { board.remembered }

    func addRemembered() async {
        let proposals = remembered
        let ids = Set(proposals.map(\.id))
        adding.formUnion(ids)
        defer { adding.subtract(ids) }
        await workspace.approveRemembered(proposals)
    }

    // MARK: Rows

    func title(_ p: Proposal) -> String {
        guard case .lms(let item) = p.source, case .difference(let d) = item.item else { return p.title ?? "" }
        switch d.change {
        case .unsubmitted: return String(localized: .lmsUnsubmittedTitle(d.lms.title))
        case .due: return String(localized: .lmsDueChangedTitle(d.lms.title))
        case .attachments: return String(localized: .lmsAttachmentsTitle(d.lms.title))
        }
    }

    // 회색 줄에는 어디서 왔는지와 꼭 필요한 한 가지만 둔다. 종류는 아이콘이, 마감은 오른쪽 글자가 말한다.
    // 전체에서만 과목을 앞에 붙이고, 받을 과목을 고르지 않은 강의실은 강의실 이름을 붙인다.
    func detail(_ p: Proposal, source: Bool) -> String? {
        guard case .lms(let item) = p.source else { return nil }
        return join([source ? place(item) : nil, lmsDetail(item, flag: p.flag)])
    }

    private func place(_ item: LMSProposal) -> String {
        if case .difference(let d) = item.item, let title = courseTitle(d.course) { return title }
        return remembered(item.classroom.id)?.title ?? item.classroom.title
    }

    private func join(_ parts: [String?]) -> String? {
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    private func lmsDetail(_ p: LMSProposal, flag: ProposalFlag?) -> String? {
        if let flag { return flag.label }
        switch p.item {
        case .assignment: return attachmentSummary(p.attachments)
        case .file(let f): return "\(CourseFolder.lectures.rawValue)/\(f.lectureName(f.title))"
        case .notice(let n): return n.author
        case .difference(let d):
            switch d.change {
            case .unsubmitted:
                let status = workspace.course(d.course)?.file.assignments.first { $0.id == d.assignment }?.status ?? .submitted
                return String(localized: .lmsFolioStatus(status.label))
            case .due(let folio, let lms):
                return String(localized: .lmsDueChange(folio.map(dueTime) ?? String(localized: .lmsNoDue), dueTime(lms)))
            case .attachments(let new): return attachmentSummary(new)
            }
        }
    }

    private func dueTime(_ date: Date) -> String {
        DateTimeText.text(date, from: workspace.now, time: true, settings: workspace.settings, calendar: workspace.calendar)
    }

    private func attachmentSummary(_ attachments: [LMSAttachment]) -> String? {
        LMSAttachment.summary(attachments).map { $0.more == 0 ? $0.first : String(localized: .lmsAttachmentsMore($0.first, $0.more)) }
    }

    // 고칠 것의 단추다. 받을 과목이 정해져 있어 과목을 고르지 않는다.
    func fixLabel(_ p: Proposal) -> String? {
        switch p.kind {
        case .lmsDue: String(localized: .lmsApplyDue)
        case .lmsAttachments: String(localized: .lmsReceiveAttachments)
        case .lmsAssignment, .lmsFile, .lmsNotice, .lmsUnsubmitted, .claude, .cleanupMove: nil
        }
    }

    func fix(_ p: Proposal) async {
        adding.insert(p.id)
        defer { adding.remove(p.id) }
        await workspace.approve([p], into: nil)
    }

    // MARK: Deadlines

    func detail(_ d: LMSDeadline, source: Bool) -> String? {
        guard source else { return nil }
        return d.course.flatMap(courseTitle) ?? remembered(d.classroom.id)?.title ?? d.classroom.title
    }

    func due(_ d: LMSDeadline) -> Due? { d.assignment.due.map(due) }

    func due(_ p: Proposal) -> Due? { p.due.map(due) }

    // 오늘 화면의 할 일처럼 칩 없이 글자의 색으로 급한 정도를 보인다.
    struct Due {
        var text: String
        var tone: Tone?
    }

    private func due(_ date: Date) -> Due {
        let days = DateTimeText.days(date, from: workspace.now, settings: workspace.settings, calendar: workspace.calendar)
        let tone: Tone? =
            switch DueUrgency(studyDays: days, settings: workspace.settings.urgency) {
            case .urgent: .danger
            case .soon: .warning
            case .later: nil
            }
        return Due(text: dueTime(date), tone: tone)
    }

    // MARK: Actions

    func addable(_ proposals: [Proposal]) -> [Proposal] { proposals.filter { $0.kind.picksCourse && $0.canApprove } }

    func isAdding(_ proposals: [Proposal]) -> Bool { !adding.isDisjoint(with: proposals.map(\.id)) }

    func add(_ proposals: [Proposal], into course: UUID) async {
        let ids = Set(proposals.map(\.id))
        adding.formUnion(ids)
        defer { adding.subtract(ids) }
        await workspace.approve(proposals, into: course)
    }

    func dismiss(_ proposals: [Proposal]) { workspace.dismiss(proposals) }

    func proposeAgain(_ h: LMSInbox.Handled) { workspace.propose(again: [h]) }

    func detail(_ h: LMSInbox.Handled) -> String {
        join([lmsDetail(h.proposal, flag: nil), h.course.flatMap(courseTitle).map { String(localized: .lmsAddedTo($0)) }]) ?? ""
    }

    // MARK: Today

    var earliestDue: String? {
        let first = board.proposals.compactMap { p -> (Date, String)? in p.due.map { ($0, title(p)) } }.min { $0.0 < $1.0 }
        return first.map { String(localized: .lmsTodayDetail(workspace.lmsTime($0.0), $0.1)) }
    }

    // 오늘 화면은 처리할 것이 있는 강의실만 수와 함께 보인다.
    var todayRows: [ProposalBoard.Room] { board.rooms.filter { !$0.proposals.isEmpty } }
}
