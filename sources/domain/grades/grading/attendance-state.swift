import FolioCore
import Foundation

public enum AttendanceState: String, Codable, Sendable, CaseIterable {
    case present, late, absent, excused
}

extension AttendanceState {
    public var tone: StatusTone {
        switch self {
        case .present: .good
        case .late: .caution
        case .absent: .bad
        case .excused: .muted
        }
    }
}
