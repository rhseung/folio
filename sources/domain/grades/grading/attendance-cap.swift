import Foundation

public struct AttendanceCap: Codable, Sendable, Hashable {
    public var absences: Int
    public var maxGrade: UUID

    public init(absences: Int, maxGrade: UUID) {
        self.absences = absences
        self.maxGrade = maxGrade
    }
}
