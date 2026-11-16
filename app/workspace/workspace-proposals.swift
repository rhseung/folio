import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    var proposalBoard: ProposalBoard {
        ProposalBoard.build(
            lms: lmsInbox, settings: settings.lms, viewerOnly: lms.viewerOnly, courses: Set(courses.map(\.file.course.id)))
    }

    @discardableResult
    func run(_ proposal: ActionProposal) -> ActionContext? {
        guard let action = Actions.action(proposal) else {
            error = String(localized: .claudeProposalUnknown)
            return nil
        }
        return run(action)
    }

    // LMS 제안은 받기 전에 이 기기가 파일을 내려받는다. 같은 종류는 목록을 받는 액션 하나로 실행한다.
    func approve(_ proposals: [Proposal], into course: UUID?) async {
        guard let ready = await downloaded(proposals) else { return }
        for action in ready.approvals(in: course) { guard run(action) != nil else { return } }
    }

    // 과목을 고르지 않고 강의실마다 기억한 과목에 받는다. 과목이 달라도 `lms accept` 하나로 받는다.
    func approveRemembered(_ proposals: [Proposal]) async {
        guard let ready = await downloaded(proposals) else { return }
        for action in ready.rememberedApprovals { guard run(action) != nil else { return } }
    }

    // 내려받아 보니 뷰어 전용인 자료는 빼고 나머지만 받는다. 그 자료는 이제 뷰어 전용으로 표시되어 열기와 무시만 남는다.
    private func downloaded(_ proposals: [Proposal]) async -> [Proposal]? {
        var ready: [Proposal] = []
        for p in proposals where p.canApprove {
            guard let got = await downloaded(p) else { return nil }
            if case .lms(let item) = p.source, case .file(let f) = item.item, lms.viewerOnly.contains(f.id) { continue }
            ready.append(got)
        }
        return ready
    }

    private func downloaded(_ p: Proposal) async -> Proposal? {
        guard case .lms(let item) = p.source else { return p }
        do {
            switch item.item {
            case .assignment(let a): return p.downloaded(files: try await lms.download(a.attachments ?? []).map(\.path))
            case .file(let f):
                // 뷰어 전용이면 받을 파일이 없고, 그 자료는 이제 뷰어 전용으로 표시된다.
                guard let url = try await lms.download(f) else { return p.downloaded() }
                return p.downloaded(file: url.path)
            case .notice, .difference: return p
            }
        } catch {
            self.error = String(localized: .lmsDownloadFailed(item.title, error.localizedDescription))
            return nil
        }
    }

    func dismiss(_ proposals: [Proposal]) {
        for action in proposals.dismissals { guard run(action) != nil else { return } }
    }

    func propose(again hidden: [LMSInbox.Handled]) {
        run(LMSMark(keys: hidden.map(\.proposal.key.description), handled: false))
    }
}
