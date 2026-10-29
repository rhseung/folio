import Foundation

/// How a component's sub-scores combine (docs/SPEC.md "GradeComponent").
/// Stored as `sum`, `mean`, `single`, `dropLowest:1`, `bestOf:3` so course.json stays readable.
public enum Aggregation: Hashable, Sendable, Codable {
    case sum
    case mean
    case dropLowest(Int)
    case bestOf(Int)
    case single

    var stored: String {
        switch self {
        case .sum: "sum"
        case .mean: "mean"
        case .single: "single"
        case .dropLowest(let n): "dropLowest:\(n)"
        case .bestOf(let n): "bestOf:\(n)"
        }
    }

    init?(stored: String) {
        let parts = stored.split(separator: ":")
        switch (parts.first, parts.count == 2 ? Int(parts[1]) : nil) {
        case ("sum", nil): self = .sum
        case ("mean", nil): self = .mean
        case ("single", nil): self = .single
        case ("dropLowest", let n?): self = .dropLowest(n)
        case ("bestOf", let n?): self = .bestOf(n)
        default: return nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let value = Aggregation(stored: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown aggregation \(s)"))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(stored)
    }
}

public struct GradeComponent: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var name: String
    /// Percent of the final score.
    public var weight: Double
    public var order: Int
    public var aggregation: Aggregation
    /// Planned number of sub-scores; lets the calculator tell how much of the component is still to come.
    public var expectedCount: Int?
    /// Components a syllabus lists under one heading (Reports: materials, results, discussion). Display and assignment
    /// scoring only; each still counts by its own weight.
    public var group: String?

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, name: String, weight: Double, order: Int = 0, aggregation: Aggregation = .sum, expectedCount: Int? = nil) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.name = name
        self.weight = weight
        self.order = order
        self.aggregation = aggregation
        self.expectedCount = expectedCount
    }
}

public struct ScoreEntry: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var componentId: UUID
    public var title: String
    public var score: Double
    public var max: Double
    /// Class mean and standard deviation, when published.
    public var mean: Double?
    public var stdDev: Double?
    public var date: LocalDate?
    public var assignmentId: UUID?
    public var examId: UUID?
    public var excused: Bool

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, componentId: UUID, title: String, score: Double, max: Double, mean: Double? = nil, stdDev: Double? = nil, excused: Bool = false) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.componentId = componentId
        self.title = title
        self.score = score
        self.max = max
        self.mean = mean
        self.stdDev = stdDev
        self.excused = excused
    }
}

/// The highest grade allowed once absences reach `absences`.
public struct AttendanceCap: Codable, Sendable, Hashable {
    public var absences: Int
    public var maxGrade: UUID

    public init(absences: Int, maxGrade: UUID) {
        self.absences = absences
        self.maxGrade = maxGrade
    }
}

public struct GradeCutoff: Codable, Sendable, Hashable {
    public var grade: UUID
    public var minScore: Double

    public init(grade: UUID, minScore: Double) {
        self.grade = grade
        self.minScore = minScore
    }
}

public struct GradePolicy: Codable, Sendable, Equatable {
    public var attendanceCap: [AttendanceCap]
    public var minAttendanceRatio: Double?
    public var latePolicy: String?
    /// Absolute-grading cutoffs, when published.
    public var cutoffs: [GradeCutoff]
    /// Rules that couldn't be structured, verbatim.
    public var notes: String
    /// Relative grading: the share of the class given an A (A+ and A0), the rest going to B and C. Nil means the default.
    public var topGradeRatio: Double?
    /// "지각 3회 = 결석 1회": every this many lates count as one absence toward the caps. Nil means lates never do.
    public var latesPerAbsence: Int?

    public static let defaultTopGradeRatio = 0.5
    public var effectiveTopGradeRatio: Double { topGradeRatio ?? Self.defaultTopGradeRatio }

    public init(attendanceCap: [AttendanceCap] = [], minAttendanceRatio: Double? = nil, latePolicy: String? = nil, cutoffs: [GradeCutoff] = [], notes: String = "") {
        self.attendanceCap = attendanceCap
        self.minAttendanceRatio = minAttendanceRatio
        self.latePolicy = latePolicy
        self.cutoffs = cutoffs
        self.notes = notes
    }
}

public enum AttendanceState: String, Codable, Sendable, CaseIterable {
    case present, late, absent, excused
}

public struct Attendance: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var sessionId: UUID
    public var state: AttendanceState

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, sessionId: UUID, state: AttendanceState) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.sessionId = sessionId
        self.state = state
    }
}
