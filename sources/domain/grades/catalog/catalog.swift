import Foundation

public struct Catalog: Codable, Sendable, Equatable {
    public var codes: [CourseCode]
    public var categories: [Category]
    public var letterGrades: [LetterGrade]
    public var people: [Person]
    public var handbooks: [Handbook]

    public init(
        codes: [CourseCode] = [], categories: [Category] = [], letterGrades: [LetterGrade] = [], people: [Person] = [],
        handbooks: [Handbook] = []
    ) {
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

    public var maxPoints: Double { letterGrades.compactMap(\.points).max() ?? 4.5 }

    public func grade(_ id: UUID?) -> LetterGrade? {
        id.flatMap { id in letterGrades.first { $0.id == id } }
    }

    public func scoped(to programs: [StudentProgram]) -> Catalog {
        let declared = Set(programs.map(\.codeId))
        func applies(_ c: Category, depth: Int = 0) -> Bool {
            guard c.programId.map(declared.contains) ?? true else { return false }
            // 손으로 고친 JSON의 부모 순환을 깊이 제한으로 막는다.
            guard depth < 16, let parent = c.parentId.flatMap(category) else { return true }
            return applies(parent, depth: depth + 1)
        }
        var copy = self
        copy.categories = categories.filter { applies($0) }
        return copy
    }

    public func program(of category: Category) -> UUID? {
        var current: Category? = category
        var steps = 0
        // 손으로 고친 JSON의 부모 순환을 단계 제한으로 막는다.
        while let c = current, steps < 16 {
            if let p = c.programId { return p }
            current = c.parentId.flatMap(self.category)
            steps += 1
        }
        return nil
    }

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
