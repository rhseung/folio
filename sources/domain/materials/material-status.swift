import FolioCore
import Foundation

public enum MaterialStatus: String, Codable, Sendable, CaseIterable {
    case classified, unclassified, missing, ignored
}

extension MaterialStatus {
    public var tone: StatusTone {
        switch self {
        case .classified: .plain
        case .unclassified: .caution
        case .missing: .bad
        case .ignored: .muted
        }
    }
}
