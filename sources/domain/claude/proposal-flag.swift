import Foundation

public enum ProposalFlag: Hashable, Sendable {
    // 정리 도구가 확신하지 못한 이동이다. 명령줄은 `--include-flagged` 없이는 옮기지 않는다.
    case review(ReviewReason)
    // LMS 문서 뷰어로만 열리는 자료다. 내려받기 제한을 우회하지 않으므로 받지 못하고 열기와 무시만 있다.
    case viewerOnly

    public var label: String {
        switch self {
        case .review(let reason): reason.label
        case .viewerOnly: String(localized: .proposalFlagViewerOnly)
        }
    }

    public var blocksApproval: Bool {
        switch self {
        case .review: false
        case .viewerOnly: true
        }
    }
}
