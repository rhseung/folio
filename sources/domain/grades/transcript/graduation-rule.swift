import Foundation

public struct GraduationRule: Codable, Sendable, Equatable {
    public var totalCredits: Double
    public var minGPA: Double
    public var admissionYear: Int?
    public var programs: [StudentProgram]
    public var email: String

    public static let defaultTotalCredits: Double = 130
    public static let defaultMinGPA = 2.0

    public init(
        totalCredits: Double = defaultTotalCredits, minGPA: Double = defaultMinGPA, admissionYear: Int? = nil,
        programs: [StudentProgram] = [], email: String = ""
    ) {
        self.totalCredits = totalCredits
        self.minGPA = minGPA
        self.admissionYear = admissionYear
        self.programs = programs
        self.email = email
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalCredits = try c.decodeIfPresent(Double.self, forKey: .totalCredits) ?? Self.defaultTotalCredits
        minGPA = try c.decodeIfPresent(Double.self, forKey: .minGPA) ?? Self.defaultMinGPA
        admissionYear = try c.decodeIfPresent(Int.self, forKey: .admissionYear)
        programs = try c.decodeIfPresent([StudentProgram].self, forKey: .programs) ?? []
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
    }
}
