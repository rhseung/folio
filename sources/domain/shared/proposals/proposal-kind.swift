import Foundation

// 제안의 종류다. LMS 탭의 무리와 행, 폴더 정리, `proposal list`(CLI와 MCP)가 이 표를 읽는다.
public enum ProposalKind: String, Codable, CaseIterable, Sendable {
    case lmsAssignment = "lms-assignment"
    case lmsFile = "lms-file"
    case lmsNotice = "lms-notice"
    case claude
    case cleanupMove = "cleanup-move"

    // 아래 switch에는 default를 두지 않는다. 새 종류는 무리, 승인 방식, 이름을 정할 때까지 컴파일되지 않아야 한다.
    // LMS 탭은 LMS 항목만 받는다. Claude 제안은 그 대화의 패널에서, 폴더 정리의 이동은 과목의 자료 화면에서 받는다.
    public var group: ProposalGroup? {
        switch self {
        case .lmsAssignment, .lmsFile: .new
        case .lmsNotice: .posts
        case .claude, .cleanupMove: nil
        }
    }

    // 강의실을 과목에 잇지 않으므로(#132) 이 종류의 제안에는 과목이 없고, 승인할 때 고른 과목을 `course`에 넣는다.
    public var picksCourse: Bool {
        switch self {
        case .lmsAssignment, .lmsFile: true
        case .lmsNotice, .claude, .cleanupMove: false
        }
    }

    // 같은 종류의 제안 여럿을 한 번에 승인하거나 무시하면, 이 필드의 목록을 이어 붙인 액션 하나로 실행한다. 그래야 한 번
    // 묻고, 하나가 막히면 아무것도 쓰기 전에 멈춘다. Claude 제안은 제안마다 액션이 달라 이어 붙이지 않는다.
    public var list: String? {
        switch self {
        case .lmsAssignment, .lmsFile, .lmsNotice: "items"
        case .cleanupMove: "moves"
        case .claude: nil
        }
    }

    public var dismissList: String? {
        switch self {
        case .lmsAssignment, .lmsFile, .lmsNotice: "keys"
        case .claude, .cleanupMove: nil
        }
    }

    public var name: String {
        switch self {
        case .lmsAssignment: String(localized: .proposalKindLmsAssignment)
        case .lmsFile: String(localized: .proposalKindLmsFile)
        case .lmsNotice: String(localized: .proposalKindLmsNotice)
        case .claude: String(localized: .proposalKindClaude)
        case .cleanupMove: String(localized: .proposalKindCleanupMove)
        }
    }
}
