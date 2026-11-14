import Foundation

public struct GradePolicy: Codable, Sendable, Equatable {
    public var attendanceCap: [AttendanceCap]
    public var minAttendanceRatio: Double?
    public var latePolicy: String?
    public var cutoffs: [GradeCutoff]
    public var notes: String
    public var topGradeRatio: Double?
    public var latesPerAbsence: Int?

    public static let defaultTopGradeRatio = 0.5
    public var effectiveTopGradeRatio: Double { topGradeRatio ?? Self.defaultTopGradeRatio }

    public init(
        attendanceCap: [AttendanceCap] = [], minAttendanceRatio: Double? = nil, latePolicy: String? = nil, cutoffs: [GradeCutoff] = [],
        notes: String = ""
    ) {
        self.attendanceCap = attendanceCap
        self.minAttendanceRatio = minAttendanceRatio
        self.latePolicy = latePolicy
        self.cutoffs = cutoffs
        self.notes = notes
    }
}
