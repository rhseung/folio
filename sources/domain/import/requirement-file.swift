import Foundation

public struct RequirementFile: Codable, Sendable {
    public struct Program: Codable, Sendable {
        public var code: String
        public var kind: StudentProgram.Kind
    }

    public var admissionYear: Int?
    public var programs: [Program]?
    public var categories: [RequirementSpec]

    public init(from decoder: any Decoder) throws {
        if let rows = try? [RequirementSpec](from: decoder) {
            categories = rows
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        admissionYear = try c.decodeIfPresent(Int.self, forKey: .admissionYear)
        programs = try c.decodeIfPresent([Program].self, forKey: .programs)
        categories = try c.decodeIfPresent([RequirementSpec].self, forKey: .categories) ?? []
    }
}
