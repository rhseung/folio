import Foundation

// 승인 화면에 오는 제안 하나다. 어디서 왔든 승인하면 `action`을, 무시하면 `dismissal`을 실행한다.
public struct Proposal: Hashable, Sendable, Identifiable {
    public var kind: ProposalKind
    public var source: ProposalSource
    // 없으면 승인할 수 없고 열기와 무시만 있다(공지, 뷰어 전용 자료).
    public var action: ActionProposal?
    public var dismissal: ActionProposal?
    public var flag: ProposalFlag?

    public init(
        kind: ProposalKind, source: ProposalSource, action: ActionProposal?, dismissal: ActionProposal? = nil,
        flag: ProposalFlag? = nil
    ) {
        self.kind = kind
        self.source = source
        self.action = action
        self.dismissal = dismissal
        self.flag = flag
    }

    public var id: String {
        switch source {
        case .lms(let p): "lms/\(p.key)"
        case .claude(let c): "claude/\(c.message.uuidString)/\(c.index)"
        case .cleanup(let m): "cleanup/\(m.from)"
        }
    }

    // Claude 제안의 이름은 액션의 완료 문구를 지금 폴더로 그려야 해서 부르는 쪽이 만든다.
    public var title: String? {
        switch source {
        case .lms(let p): p.title
        case .claude: nil
        case .cleanup(let m): m.from
        }
    }

    public var due: Date? {
        if case .lms(let p) = source, case .assignment(let a) = p.item { return a.due }
        return nil
    }

    public var url: URL? {
        if case .lms(let p) = source { return p.url }
        return nil
    }

    public var canApprove: Bool { action != nil && flag?.blocksApproval != true }

    public var canDismiss: Bool {
        switch source {
        case .lms: dismissal != nil
        case .claude, .cleanup: false
        }
    }

    // 승인할 때 고른 과목을 넣는다. 과목을 고르는 종류는 과목 없이 승인하지 못한다. Claude 제안은 입력에 과목이 이미
    // 있으므로 부르는 쪽이 과목을 주지 않는다.
    public func action(in course: UUID?) -> ActionProposal? {
        guard var action else { return nil }
        guard let course else { return kind.picksCourse ? nil : action }
        action.input["course"] = .string(course.uuidString)
        return action
    }
}

extension [Proposal] {
    // 같은 명령끼리 목록 필드를 이어 붙여 액션 하나로 만든다. 목록 필드가 없는 종류(Claude)는 하나씩 둔다.
    public func approvals(in course: UUID?) -> [ActionProposal] {
        Self.joined(filter(\.canApprove).map { ($0.kind.list, $0.action(in: course)) })
    }

    // 과목 없이 받으면 `lms accept`가 항목의 강의실마다 기억한 과목에 넣는다. 그래서 과목이 다른 강의실의 항목도 액션
    // 하나로 받는다.
    public var rememberedApprovals: [ActionProposal] {
        Self.joined(filter(\.canApprove).map { ($0.kind.list, $0.action) })
    }

    public var dismissals: [ActionProposal] {
        Self.joined(map { ($0.kind.dismissList, $0.dismissal) })
    }

    private static func joined(_ items: [(list: String?, action: ActionProposal?)]) -> [ActionProposal] {
        var out: [ActionProposal] = []
        for (list, action) in items {
            guard let action else { continue }
            if let list, let i = out.firstIndex(where: { $0.joins(action, on: list) }),
                case .array(let more)? = action.input[list], case .array(let have)? = out[i].input[list]
            {
                out[i].input[list] = .array(have + more)
            } else {
                out.append(action)
            }
        }
        return out
    }
}

extension ActionProposal {
    // 목록 필드 밖의 입력(과목)이 같은 같은 명령만 잇는다. 다른 과목에 받을 항목을 한 액션에 넣으면 엉뚱한 과목에 들어간다.
    func joins(_ other: ActionProposal, on list: String) -> Bool {
        guard command == other.command, case .object(var a) = input, case .object(var b) = other.input else { return false }
        a[list] = nil
        b[list] = nil
        return a == b
    }
}
