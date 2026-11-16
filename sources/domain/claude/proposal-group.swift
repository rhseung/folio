import Foundation

// LMS 탭 "전체"의 무리이고, 선언한 차례대로 선다(Folio와 다른 것, 새로 올라온 것, 이번 주 기한, 새 글).
// 이번 주 기한은 제안이 아니라 보기만 하는 행이라 이 표에 없고, 화면이 새 글 앞에 둔다(`ProposalBoard.deadlines`).
public enum ProposalGroup: String, CaseIterable, Sendable {
    case differs, new, posts

    public var name: String {
        switch self {
        case .differs: String(localized: .proposalGroupDiffers)
        case .new: String(localized: .proposalGroupNew)
        case .posts: String(localized: .proposalGroupPosts)
        }
    }
}
