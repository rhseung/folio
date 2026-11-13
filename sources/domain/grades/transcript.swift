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

public struct StudentProgram: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case major, doubleMajor, minor, intensive
    }

    public var codeId: UUID
    public var kind: Kind

    public init(codeId: UUID, kind: Kind) {
        self.codeId = codeId
        self.kind = kind
    }
}

public struct Semester: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var year: Int
    public var term: Term
    public var start: LocalDate?
    public var end: LocalDate?
    public var order: Int { year * 10 + (term.folderNumber ?? 0) }
    public var creditedHours: Double?
    public var source: String?
    public var memo: String
    public var midtermWeek: Int?
    public var finalWeek: Int?

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date,
        year: Int, term: Term, start: LocalDate? = nil, end: LocalDate? = nil,
        creditedHours: Double? = nil, source: String? = nil, memo: String = ""
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.year = year
        self.term = term
        self.start = start
        self.end = end
        self.creditedHours = creditedHours
        self.source = source
        self.memo = memo
    }

    // GIST의 정규 학기는 16주이고 시험 주가 하나씩 있다. 중간고사는 8주차, 기말고사는 마지막 주이다.
    public var defaultExamWeeks: (midterm: Int, final: Int)? {
        term == .spring || term == .fall ? (8, 16) : nil
    }

    public var examWeeks: Set<Int> {
        Set([midtermWeek ?? defaultExamWeeks?.midterm, finalWeek ?? defaultExamWeeks?.final].compactMap { $0 })
    }

    public var folder: SemesterFolder? {
        SemesterFolder(year: year, term: term)
    }

    public var coursesFolder: String? {
        folder?.name ?? source.flatMap(StandardLayout.creditedFolder(source:))
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
