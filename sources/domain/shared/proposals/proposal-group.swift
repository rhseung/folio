import Foundation

// LMS 탭 "전체"의 무리이고, 선언한 차례대로 선다(#132 "전체"의 차례). Folio와 다른 것과 이번 주 기한은 그 값을 LMS에서
// 읽게 될 때 이 표에 더한다.
public enum ProposalGroup: String, CaseIterable, Sendable {
    case new, claude, posts

    public var name: String {
        switch self {
        case .new: String(localized: .proposalGroupNew)
        case .claude: String(localized: .proposalGroupClaude)
        case .posts: String(localized: .proposalGroupPosts)
        }
    }
}
