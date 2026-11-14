import Foundation

public struct Transcript: Codable, Sendable, Equatable {
    public var semesters: [Semester]
    public var unfiledCourses: [Course]
    public var targetGPA: Double?
    public var graduation: GraduationRule

    public init(semesters: [Semester] = [], targetGPA: Double? = nil, graduation: GraduationRule = .init()) {
        self.semesters = semesters
        self.unfiledCourses = []
        self.targetGPA = targetGPA
        self.graduation = graduation
    }

    enum CodingKeys: String, CodingKey { case semesters, unfiledCourses, targetGPA, graduation }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        semesters = try c.decodeIfPresent([Semester].self, forKey: .semesters) ?? []
        unfiledCourses = try c.decodeIfPresent([Course].self, forKey: .unfiledCourses) ?? []
        targetGPA = try c.decodeIfPresent(Double.self, forKey: .targetGPA)
        graduation = try c.decodeIfPresent(GraduationRule.self, forKey: .graduation) ?? .init()
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(semesters, forKey: .semesters)
        if !unfiledCourses.isEmpty { try c.encode(unfiledCourses, forKey: .unfiledCourses) }
        try c.encodeIfPresent(targetGPA, forKey: .targetGPA)
        try c.encode(graduation, forKey: .graduation)
    }
}

extension [Semester] {
    // 날짜를 늦게 채우는 일이 많으므로, 시작일이 없는 학기는 시작한 것으로 본다. 인정학기는 날짜와 학기 폴더가
    // 없으므로 지금 학기가 되지 않는다.
    public func current(on today: LocalDate) -> Semester? {
        let terms = filter { $0.term != .credited }.sorted { $0.order < $1.order }
        return terms.last { ($0.start.map { $0 <= today } ?? false) && ($0.end.map { today <= $0 } ?? true) }
            ?? terms.last { ($0.start ?? today) <= today } ?? terms.first
    }
}
