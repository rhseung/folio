import Foundation

/// docs/SPEC.md "졸업 요건": what on the requirements page waits on the student, worked out once for the app and
/// `folio requirement check`. `catalog` is already scoped to the declared programs.
/// A new check adds a `Kind`, its field here and whatever it reads (a course database, say) to `init`.
public struct RequirementAudit: Sendable, Equatable {
    /// The checks by name; `folio requirement check --only` takes these.
    public enum Kind: String, CaseIterable, Sendable {
        case handbook, shared, unallowed, unassigned
    }

    /// Courses whose handbook table (HUS, PPE, ...) for the year taken names another category.
    public var suggestions: [HandbookClassifier.Suggestion]
    /// Capped categories sharing more than their cap with another program.
    public var overShared: [SharedCredits]
    /// Capped categories with courses listed under another program too that may not be shared.
    public var unallowed: [SharedCredits]
    /// Courses that count toward credits but sit in no category.
    public var unassigned: [Course]

    public init(courses: [Course], semesters: [Semester], catalog: Catalog) {
        suggestions = HandbookClassifier.suggest(courses: courses, semesters: semesters, catalog: catalog)
        let shared = GPACalculator.shared(courses: courses, catalog: catalog)
        overShared = shared.filter(\.isOver)
        unallowed = shared.filter { !$0.unallowed.isEmpty }
        unassigned = courses.filter { $0.categoryIds.isEmpty && catalog.grade($0.finalGrade)?.earnsCredits != false }
    }

    public var isEmpty: Bool { suggestions.isEmpty && overShared.isEmpty && unallowed.isEmpty && unassigned.isEmpty }

    /// Only these checks' findings; the rest come back empty.
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
    /// The area each year's handbook gives a code such as `HS2734`, oldest first; for a course not taken yet.
    public static func areas(of code: String, catalog: Catalog) -> [(year: Int, area: String)] {
        catalog.handbooks.compactMap { h in h.areas[code.uppercased()].map { (h.year, $0) } }.sorted { $0.year < $1.year }
    }
}
