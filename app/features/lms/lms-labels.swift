import FolioDomain

extension ProposalKind {
    var symbol: String {
        switch self {
        case .lmsAssignment: "checklist"
        case .lmsFile: "doc.text"
        case .lmsNotice: "text.bubble"
        case .lmsSubmitted: "checkmark.circle"
        case .lmsDue: "calendar.badge.clock"
        case .claude: "sparkles"
        case .cleanupMove: "folder"
        }
    }
}
