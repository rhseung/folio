import FolioDomain
import FolioStorage
import Foundation

@Action(
    "requirement accept", "학사편람의 분류 제안 받아들이기. 여러 과목이면 확인을 받는다",
    confirm: "과목 {courses}의 분류를 학사편람대로 바꿉니다.", done: "과목 {courses}의 분류를 학사편람대로 바꿨습니다",
    phrases: ["학사편람 분류 적용", "분류 제안 적용", "제안 모두 적용"], cli: .manual(reason: "과목을 빼면 졸업 요건 검사가 제안한 과목을 모두 고른다"))
public struct RequirementAccept {
    /// 과목
    @Arg var courses: [Course.ID]

    public func run(_ ctx: ActionContext) throws {
        let catalog = try ctx.catalog().scoped(to: ctx.transcript().graduation.programs)
        let picked = try courses.map { try ctx.file($0).course }
        let suggested = Dictionary(
            keepingFirst: HandbookClassifier.suggest(courses: picked, semesters: try ctx.transcript().semesters, catalog: catalog)
                .map { ($0.courseId, $0.categoryIds) })
        let changes = try picked.map { c in
            guard let ids = suggested[c.id] else { throw ActionError.rule(String(localized: .errorRequirementNoSuggestion(c.title))) }
            return (c.id, ids)
        }
        for (id, ids) in changes { try ctx.edit(id) { $0.course.categoryIds = ids } }
    }
}
