import Foundation

public enum AttendanceState: String, Codable, Sendable, CaseIterable {
    case present, late, absent, excused
}
