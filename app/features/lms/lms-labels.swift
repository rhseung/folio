import FolioDomain

extension ProposalKind {
    var symbol: String {
        switch self {
        case .lmsAssignment: "checklist"
        case .lmsFile: "doc.text"
        case .lmsNotice: "text.bubble"
        case .claude: "sparkles"
        case .cleanupMove: "folder"
        }
    }
}
