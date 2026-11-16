import FolioDomain

extension ProposalKind {
    var symbol: String {
        switch self {
        case .lmsAssignment: "checklist"
        case .lmsFile: "doc.text"
        case .lmsNotice: "text.bubble"
        case .lmsUnsubmitted: "exclamationmark.circle"
        case .lmsDue: "calendar.badge.clock"
        case .lmsAttachments: "paperclip"
        case .claude: "sparkles"
        case .cleanupMove: "folder"
        }
    }
}
