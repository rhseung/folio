import FolioDomain
import FolioStorage
import Foundation

@Action(
    "import handbook", "학사편람 분류 표",
    discussion: "같은 해 표는 바꾼다. 과목의 분류 제안을 보여 주며, 앱의 졸업 요건 화면에서 승인하거나 --accept로 바로 적용한다.",
    done: "학사편람을 가져왔습니다",
    examples: [
        "folio import handbook ~/Downloads/handbook-2023.json --dry-run", "folio import handbook ~/Downloads/handbook-2023.json --accept",
    ],
    phrases: ["학사편람 가져오기"])
public struct ImportHandbook {
    /// Handbook JSON
    @Arg @FromFile("handbook.json") var handbook: Handbook
    /// 분류 제안을 과목에 바로 적용
    var accept: Bool = false

    public func run(_ ctx: ActionContext) throws {
        var catalog = try ctx.catalog()
        let unknown = Set(handbook.areas.values).subtracting(catalog.categories.map(\.name))
        guard unknown.isEmpty else {
            throw ActionError.rule(String(localized: .errorImportUnknownCategory(unknown.sorted().joined(separator: ", "))))
        }

        catalog.handbooks.removeAll { $0.year == handbook.year }
        catalog.handbooks.append(handbook)
        catalog.handbooks.sort { $0.year < $1.year }
        for (name, n) in Dictionary(grouping: handbook.areas.values, by: { $0 }).mapValues(\.count).sorted(by: { $0.key < $1.key }) {
            ctx.note(String(localized: .noteImportHandbookArea(handbook.year, name, n)))
        }

        let courses = try ctx.gist.allCourses()
        let suggestions = HandbookClassifier.suggest(courses: courses, semesters: try ctx.transcript().semesters, catalog: catalog)
        for s in suggestions {
            ctx.note(
                String(
                    localized: .noteImportHandbookSuggestion(
                        courses.first { $0.id == s.courseId }!.title, s.code, catalog.category(s.categoryId)!.name)))
        }
        try ctx.editCatalog { $0.handbooks = catalog.handbooks }

        guard accept else { return }
        let byId = Dictionary(keepingFirst: suggestions.map { ($0.courseId, $0.categoryIds) })
        for id in try courseIDs(ctx).values.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let ids = byId[id] else { continue }
            try ctx.edit(id) { $0.course.categoryIds = ids }
        }
    }
}
