import Foundation

public struct GraduationRule: Codable, Sendable, Equatable {
    public var totalCredits: Double
    public var minGPA: Double
    public var admissionYear: Int?
    public var programs: [StudentProgram]
    public var email: String

    public init(
        totalCredits: Double = 130, minGPA: Double = 2.0, admissionYear: Int? = nil, programs: [StudentProgram] = [], email: String = ""
    ) {
        self.totalCredits = totalCredits
        self.minGPA = minGPA
        self.admissionYear = admissionYear
        self.programs = programs
        self.email = email
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalCredits = try c.decodeIfPresent(Double.self, forKey: .totalCredits) ?? 130
        minGPA = try c.decodeIfPresent(Double.self, forKey: .minGPA) ?? 2.0
        admissionYear = try c.decodeIfPresent(Int.self, forKey: .admissionYear)
        programs = try c.decodeIfPresent([StudentProgram].self, forKey: .programs) ?? []
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
    }
}
