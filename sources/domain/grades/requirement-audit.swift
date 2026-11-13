import Foundation

public struct RequirementAudit: Sendable, Equatable {
    // `folio requirement check --only`가 이 raw value를 검사 이름으로 받는다.
    public enum Kind: String, CaseIterable, Sendable {
        case handbook, shared, unallowed, unassigned
    }

    public var suggestions: [HandbookClassifier.Suggestion]
    public var overShared: [SharedCredits]
    public var unallowed: [SharedCredits]
    public var unassigned: [Course]

    public init(courses: [Course], semesters: [Semester], catalog: Catalog) {
        suggestions = HandbookClassifier.suggest(courses: courses, semesters: semesters, catalog: catalog)
        let shared = GPACalculator.shared(courses: courses, catalog: catalog)
        overShared = shared.filter(\.isOver)
        unallowed = shared.filter { !$0.unallowed.isEmpty }
        unassigned = courses.filter { $0.categoryIds.isEmpty && catalog.grade($0.finalGrade)?.earnsCredits != false }
    }

    public var isEmpty: Bool { suggestions.isEmpty && overShared.isEmpty && unallowed.isEmpty && unassigned.isEmpty }

    public func keeping(_ kinds: Set<Kind>) -> RequirementAudit {
        var a = self
        if !kinds.contains(.handbook) { a.suggestions = [] }
        if !kinds.contains(.shared) { a.overShared = [] }
        if !kinds.contains(.unallowed) { a.unallowed = [] }
        if !kinds.contains(.unassigned) { a.unassigned = [] }
        return a
    }
}

extension HandbookClassifier {
    public static func areas(of code: String, catalog: Catalog) -> [(year: Int, area: String)] {
        catalog.handbooks.compactMap { h in h.areas[code.uppercased()].map { (h.year, $0) } }.sorted { $0.year < $1.year }
    }
}
