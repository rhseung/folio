import Foundation

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
