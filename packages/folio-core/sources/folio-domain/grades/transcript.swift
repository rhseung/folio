import Foundation

/// `GIST/.folio/transcript.json`.
/// Every course lives in its own folder's course.json; this file holds the terms and degree-wide rules.
public struct Transcript: Codable, Sendable, Equatable {
    public var semesters: [Semester]
    /// Courses schema v1 kept here without a folder. Nothing adds to it: `transcript move` gives each its folder and
    /// empties it, and until then they count nowhere.
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

    // The key leaves the file once the courses are moved, so a moved transcript.json shows no trace of them.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(semesters, forKey: .semesters)
        if !unfiledCourses.isEmpty { try c.encode(unfiledCourses, forKey: .unfiledCourses) }
        try c.encodeIfPresent(targetGPA, forKey: .targetGPA)
        try c.encode(graduation, forKey: .graduation)
    }
}

/// Degree-wide rules from the handbook (학칙 제68조); per-category ones live on `Category`.
/// It also holds the student's own info (내 정보): the track, which decides which program-specific categories apply, and the school mail.
public struct GraduationRule: Codable, Sendable, Equatable {
    public var totalCredits: Double
    public var minGPA: Double
    /// The handbook's requirement table is chosen by admission year (학번).
    public var admissionYear: Int?
    public var programs: [StudentProgram]
    /// The account mail to professors is written from.
    public var email: String

    public init(totalCredits: Double = 130, minGPA: Double = 2.0, admissionYear: Int? = nil, programs: [StudentProgram] = [], email: String = "") {
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

/// A declared program, pointing at the department's course code.
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

/// Totals and GPA are never stored; they are computed from the semester's courses.
public struct Semester: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var year: Int
    public var term: Term
    public var start: LocalDate?
    public var end: LocalDate?
    /// Sorts semesters in time order; credited terms (no folder number) come first in their year.
    public var order: Int { year * 10 + (term.folderNumber ?? 0) }
    /// Only for `credited` terms; regular terms sum their courses.
    public var creditedHours: Double?
    /// Only for `credited` terms: where the credits came from (`영재고 AP`), which names the term's folder.
    public var source: String?
    public var memo: String
    /// The weeks whose classes give way to midterms and to finals, counted as sessions count them. Nil takes the
    /// term's default.
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

    /// GIST's regular terms run 16 weeks with one exam week each, midterms in the 8th and finals in the last.
    public var defaultExamWeeks: (midterm: Int, final: Int)? {
        term == .spring || term == .fall ? (8, 16) : nil
    }

    public var examWeeks: Set<Int> {
        Set([midtermWeek ?? defaultExamWeeks?.midterm, finalWeek ?? defaultExamWeeks?.final].compactMap { $0 })
    }

    /// Derived from year and term rather than stored, so the two can't disagree. Nil for credited terms.
    public var folder: SemesterFolder? {
        SemesterFolder(year: year, term: term)
    }

    /// Where the term's course folders go, relative to the GIST root: `2026-3`, or `_Credited/<source>`. Nil for a
    /// credited term without a source yet.
    public var coursesFolder: String? {
        folder?.name ?? source.flatMap(StandardLayout.creditedFolder(source:))
    }
}

extension [Semester] {
    /// The term `today` falls in by its dates; otherwise the newest one started, where a term without a start counts as
    /// started (dates are often filled in late); with none started, the next to start. A credited term is never current:
    /// it has no dates and no term folder to add to.
    public func current(on today: LocalDate) -> Semester? {
        let terms = filter { $0.term != .credited }.sorted { $0.order < $1.order }
        return terms.last { ($0.start.map { $0 <= today } ?? false) && ($0.end.map { today <= $0 } ?? true) }
            ?? terms.last { ($0.start ?? today) <= today } ?? terms.first
    }
}
