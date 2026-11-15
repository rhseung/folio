import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    // 모든 과목의 대화 파일이다. 사이드바가 그릴 때마다 읽으므로 대화나 폴더가 바뀔 때만 다시 읽는다.
    var courseChats: [CourseChatFile] {
        let key = [chatsRevision, dataRevision]
        if let cache = chatCache, cache.key == key { return cache.chats }
        let chats = courses.flatMap { c in ((try? c.store.chats()) ?? []).map { CourseChatFile(course: c.id, doc: $0) } }
        chatCache = (key, chats)
        return chats
    }

    var appliedProposals: Set<UUID> { Set(courses.flatMap { $0.file.appliedProposals ?? [] }) }

    var proposalBoard: ProposalBoard {
        let applied = appliedProposals
        return ProposalBoard.build(
            lms: lmsInbox, viewerOnly: lms.viewerOnly,
            chats: courseChats.map { .init(course: $0.course, chat: $0.doc.model.markingApplied(applied)) }, targets: Actions.targets)
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
        let chats = proposals.compactMap { p -> ChatProposal? in if case .claude(let c) = p.source { c } else { nil } }
        for c in chats { editChat(c) { $0.dismissed = true } }
    }

    func propose(again hidden: [LMSInbox.Handled]) {
        run(LMSMark(keys: hidden.map(\.proposal.key.description), handled: false))
    }

    // MARK: Claude proposals

    // 앞 제안을 무시했거나, 뒤 제안에 대체됐거나, 지금 폴더에서 막히면 그 앞 제안에 기대는 제안도 막힌다.
    func waiting(_ c: ChatProposal) -> ChatMessage.Waiting? {
        guard let chat = chatFile(c)?.doc.model.markingApplied(appliedProposals),
            let message = chat.messages.first(where: { $0.id == c.message })
        else { return nil }
        let proposals = message.proposals ?? []
        let superseded = chat.supersededProposals(targets: Actions.targets)
        return message.waiting(c.index) { j in
            proposals[j].dismissed == true || superseded.contains(ProposalRef(message: message.id, index: j))
                || Actions.action(proposals[j]).flatMap { refusal($0) } != nil
        }
    }

    // 확인 문구가 있는 액션이면 묻고(`PendingAction`), 없으면 바로 적용한다.
    func ask(_ c: ChatProposal) -> PendingAction? {
        guard let action = Actions.action(c.proposal) else {
            error = String(localized: .claudeProposalUnknown)
            return nil
        }
        if let waiting = waiting(c) {
            error = waiting.reason
            return nil
        }
        guard let question = confirmation(action) else {
            apply(c, action)
            return nil
        }
        return PendingAction(question: question, refusal: refusal(action), button: .claudeProposalApply, role: nil) { [weak self] in
            self?.apply(c, action)
        }
    }

    private func apply(_ c: ChatProposal, _ action: any Action) {
        editChat(c) { p in
            let proposal = p
            _ = run(action, proposal, marking: &p)
        }
    }

    // 다른 기기가 먼저 적용한 제안은 실행하기 전에 멈추고(`ActionError.applied`) 적용된 것으로 남긴다.
    func run(_ action: any Action, _ proposal: ActionProposal, marking p: inout ActionProposal) -> Bool {
        do {
            do { _ = try runThrowing(action, proposal: proposal) } catch let e as ActionError where e == .applied {}
            p.applied = true
            p.failure = nil
            return true
        } catch {
            p.failure = "\(error)"
            self.error = "\(error)"
            return false
        }
    }

    private func chatFile(_ c: ChatProposal) -> CourseChatFile? {
        courseChats.first { $0.course == c.course && $0.doc.model.id == c.chat }
    }

    private func editChat(_ c: ChatProposal, _ change: (inout ActionProposal) -> Void) {
        guard var file = chatFile(c), let m = file.doc.model.messages.firstIndex(where: { $0.id == c.message }),
            var proposals = file.doc.model.messages[m].proposals, proposals.indices.contains(c.index)
        else { return }
        change(&proposals[c.index])
        file.doc.model.messages[m].proposals = proposals
        file.doc.model.touch(by: device, at: .now)
        saveChat(file.doc, in: c.course)
    }
}

extension ChatMessage.Waiting {
    var reason: String {
        switch self {
        case .earlier(let before): String(localized: .claudeProposalWaiting(before.map { String($0 + 1) }.joined(separator: ", ")))
        case .blocked(let before): String(localized: .claudeProposalWaitingBlocked(before.map { String($0 + 1) }.joined(separator: ", ")))
        }
    }
}
