import Foundation

/// One year's handbook (학사편람) table of which category each listed course belongs to, e.g. `HS2734` → `PPE`.
/// Values are category names, so the table decides the mapping and code never names a category.
public struct Handbook: Codable, Sendable, Equatable {
    public var year: Int
    public var source: String
    public var areas: [String: String]

    public init(year: Int, source: String, areas: [String: String]) {
        self.year = year
        self.source = source
        self.areas = areas
    }
}

public enum HandbookClassifier {
    public struct Suggestion: Sendable, Equatable, Identifiable {
        public var id: UUID { courseId }
        public var courseId: UUID
        public var code: String
        public var year: Int
        public var categoryId: UUID
        /// The course's categories after applying: other categories this table assigns are replaced.
        public var categoryIds: [UUID]
    }

    /// A course is looked up only in the handbook of the year it was taken, since areas move between years.
    /// Each of its codes is tried, so a course listed as both `PP2734` and `HS2734` is found under `HS2734`.
    public static func suggest(courses: [Course], semesters: [Semester], catalog: Catalog) -> [Suggestion] {
        let years = Dictionary(semesters.map { ($0.id, $0.year) }, uniquingKeysWith: { a, _ in a })
        return courses.compactMap { course in
            guard let year = course.semesterId.flatMap({ years[$0] }),
                  let handbook = catalog.handbooks.first(where: { $0.year == year }) else { return nil }
            let number = course.number.split(separator: "-").first.map(String.init) ?? ""  // the handbook lists 2734, not section 2734-01
            let codes = course.codes.compactMap { id in catalog.codes.first { $0.id == id }?.prefix }.map { $0 + number }
            guard let code = codes.first(where: { handbook.areas[$0] != nil }),
                  let target = catalog.categories.first(where: { $0.name == handbook.areas[code] }),
                  !course.categoryIds.contains(target.id) else { return nil }
            let managed = Set(handbook.areas.values)
            let kept = course.categoryIds.filter { id in catalog.category(id).map { !managed.contains($0.name) } ?? true }
            let ids = kept + [target.id]
            return Suggestion(courseId: course.id, code: code, year: year, categoryId: target.id, categoryIds: ids)
        }
    }
}
