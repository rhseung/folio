import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    var proposalBoard: ProposalBoard { ProposalBoard.build(lms: lmsInbox, viewerOnly: lms.viewerOnly) }

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
        var ready: [Proposal] = []
        for p in proposals where p.canApprove {
            guard let got = await downloaded(p) else { return }
            ready.append(got)
        }
        for action in ready.approvals(in: course) { guard run(action) != nil else { return } }
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
            case .notice: return p
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
