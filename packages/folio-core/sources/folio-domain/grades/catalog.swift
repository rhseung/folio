import Foundation

/// `GIST/.folio/catalog.json`: lookup tables shared by every course.
public struct Catalog: Codable, Sendable, Equatable {
    public var codes: [CourseCode]
    public var categories: [Category]
    public var letterGrades: [LetterGrade]
    public var people: [Person]
    public var handbooks: [Handbook]

    public init(codes: [CourseCode] = [], categories: [Category] = [], letterGrades: [LetterGrade] = [], people: [Person] = [], handbooks: [Handbook] = []) {
        self.codes = codes
        self.categories = categories
        self.letterGrades = letterGrades
        self.people = people
        self.handbooks = handbooks
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        codes = try c.decodeIfPresent([CourseCode].self, forKey: .codes) ?? []
        categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
        letterGrades = try c.decodeIfPresent([LetterGrade].self, forKey: .letterGrades) ?? []
        people = try c.decodeIfPresent([Person].self, forKey: .people) ?? []
        handbooks = try c.decodeIfPresent([Handbook].self, forKey: .handbooks) ?? []
    }

    /// The top of the grade scale, read from the letter grades; 4.5 only until a catalog is imported.
    public var maxPoints: Double { letterGrades.compactMap(\.points).max() ?? 4.5 }

    public func grade(_ id: UUID?) -> LetterGrade? {
        id.flatMap { id in letterGrades.first { $0.id == id } }
    }

    /// Only the categories that apply to these programs. A child of a hidden category is hidden too.
    public func scoped(to programs: [StudentProgram]) -> Catalog {
        let declared = Set(programs.map(\.codeId))
        func applies(_ c: Category, depth: Int = 0) -> Bool {
            guard c.programId.map(declared.contains) ?? true else { return false }
            guard depth < 16, let parent = c.parentId.flatMap(category) else { return true }  // depth guards a parent cycle in hand-edited JSON
            return applies(parent, depth: depth + 1)
        }
        var copy = self
        copy.categories = categories.filter { applies($0) }
        return copy
    }

    /// The program a category belongs to: its own, else the nearest ancestor's.
    public func program(of category: Category) -> UUID? {
        var current: Category? = category
        var steps = 0
        // The step limit stops a parent cycle in hand-edited JSON.
        while let c = current, steps < 16 {
            if let p = c.programId { return p }
            current = c.parentId.flatMap(self.category)
            steps += 1
        }
        return nil
    }

    /// The grades a course in this mode can get, best first.
    public func grades(for mode: GradingMode) -> [LetterGrade] {
        letterGrades.filter { $0.applies(to: mode) }.sorted { ($0.points ?? -1) > ($1.points ?? -1) }
    }

    public func category(_ id: UUID) -> Category? {
        categories.first { $0.id == id }
    }

    public func code(_ id: UUID) -> CourseCode? {
        codes.first { $0.id == id }
    }
}

public struct CourseCode: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    /// `EC`, `GS`, ...
    public var prefix: String
    public var department: String
    public var program: String
    /// Which yearly handbook (학사편람) the code comes from.
    public var source: String

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, prefix: String, department: String = "", program: String = "", source: String = "") {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.prefix = prefix
        self.department = department
        self.program = program
        self.source = source
    }
}

public struct Category: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var name: String
    /// Grouping used by graduation requirements.
    public var group: String
    public var isMajor: Bool
    public var parentId: UUID?
    /// Graduation requirement for this category, entered from the handbook.
    public var minCredits: Double?
    public var maxCredits: Double?
    /// Passed courses required, for zero-credit requirements such as colloquia and arts/PE semesters.
    public var minCount: Int?
    /// Which courses count and where the numbers come from, as written in the handbook.
    public var rule: String?
    /// The program (a course code) this requirement belongs to; nil for ones every student has.
    public var programId: UUID?
    /// Most credits its courses may also count toward another program's categories: 9 for a double major, 0 for a
    /// minor (학사편람). The student picks which by putting a course in both; what goes past this is not counted here.
    public var maxSharedCredits: Double?

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, name: String, group: String = "", isMajor: Bool = false,
                parentId: UUID? = nil, minCredits: Double? = nil, maxCredits: Double? = nil, minCount: Int? = nil, rule: String? = nil) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.name = name
        self.group = group
        self.isMajor = isMajor
        self.parentId = parentId
        self.minCredits = minCredits
        self.maxCredits = maxCredits
        self.minCount = minCount
        self.rule = rule
    }
}

/// A grade symbol and how it counts. S, U, W, P and F live here too, so no symbol is special-cased in code.
public struct LetterGrade: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var symbol: String
    /// Grade points (A+ = 4.5). Nil for symbols without points (S, U, W).
    public var points: Double?
    public var countsInGpa: Bool
    public var countsInCredits: Bool
    /// Whether the credits count toward graduation and requirement categories. Nil follows `countsInCredits`;
    /// W sets it off, since it counts in the semester's total (as Notion and the transcript do) but earns nothing.
    public var countsTowardGraduation: Bool?
    public var earnsCredits: Bool { countsTowardGraduation ?? countsInCredits }
    /// Grading modes this symbol is given in. Nil infers it: symbols with points only in letter-graded courses,
    /// the rest (S, U, W) anywhere. S and W look the same otherwise, so S/U set it to keep out of letter courses.
    public var modes: [GradingMode]?

    public func applies(to mode: GradingMode) -> Bool {
        modes.map { $0.contains(mode) } ?? (points == nil || mode != .passFail)
    }

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, symbol: String, points: Double?, countsInGpa: Bool, countsInCredits: Bool) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.symbol = symbol
        self.points = points
        self.countsInGpa = countsInGpa
        self.countsInCredits = countsInCredits
    }
}

public enum PersonRole: String, Codable, Sendable, CaseIterable {
    case professor, assistant, lecturer
}

public struct Person: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var name: String
    public var email: String
    public var role: PersonRole
    public var office: String
    public var officeHours: String
    public var memo: String

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, name: String, email: String = "", role: PersonRole = .professor, office: String = "", officeHours: String = "", memo: String = "") {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.name = name
        self.email = email
        self.role = role
        self.office = office
        self.officeHours = officeHours
        self.memo = memo
    }
}
