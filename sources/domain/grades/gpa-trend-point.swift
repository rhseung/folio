import Foundation

public struct GPATrendPoint: Sendable, Equatable {
    public var semester: Semester
    public var gpa: Double
    public var credits: Double
    public var cumulative: Double?

    public init(semester: Semester, gpa: Double, credits: Double, cumulative: Double?) {
        self.semester = semester
        self.gpa = gpa
        self.credits = credits
        self.cumulative = cumulative
    }
}
