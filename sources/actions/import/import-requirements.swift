import FolioDomain
import FolioStorage
import Foundation

@Action(
    "import requirements", "졸업 요건 분류와 학생 정보", discussion: "강의 코드 표에 없는 코드가 있으면 실행하지 않는다(종료 코드 4).",
    done: "졸업 요건을 가져왔습니다", examples: ["folio import requirements ~/Downloads/requirements.json --dry-run"], phrases: ["졸업 요건 가져오기"])
public struct ImportRequirements {
    /// RequirementFile JSON
    @Arg @FromFile("requirements.json") var file: RequirementFile

    public func run(_ ctx: ActionContext) throws {
        let catalog = try ctx.catalog()
        let codes = catalog.codes
        for prefix in Set(file.categories.compactMap(\.program) + (file.programs ?? []).map(\.code))
        where RequirementImporter.code(prefix, in: codes) == nil {
            throw ActionError.rule(String(localized: .errorImportUnknownCode(prefix)))
        }

        let r = RequirementImporter.merge(file.categories, into: catalog.categories, codes: codes, device: ctx.device, now: ctx.now)
        let fmt = { (c: FolioDomain.Category) in
            let parent = c.parentId.flatMap { id in r.categories.first { $0.id == id }?.name }.map { " ⊂ \($0)" } ?? ""
            let credits = [
                c.minCredits.map { String(localized: .valueCreditsMin($0.formatted())) },
                c.maxCredits.map { String(localized: .valueCreditsMax($0.formatted())) },
                c.minCount.map { String(localized: .valueCourseCount($0)) },
                c.maxSharedCredits.map { String(localized: .valueCreditsShared($0.formatted())) },
            ].compactMap { $0 }.joined(separator: ", ")
            let program = c.programId.flatMap { id in codes.first { $0.id == id }?.prefix }.map { " (\($0))" } ?? ""
            return "\(c.name) [\(c.group)]\(program)\(parent) \(credits)"
        }

        for name in r.added { ctx.note("+ " + fmt(r.categories.first { $0.name == name }!)) }
        for name in r.changed {
            let after = r.categories.first { $0.name == name }!
            let before = catalog.categories.first { $0.id == after.id }!
            ctx.note(
                "~ " + fmt(after) + (before.name != after.name ? String(localized: .noteImportRequirementsRenamed(before.name)) : "")
                    + String(localized: .noteImportRequirementsBefore) + fmt(before))
        }
        for name in r.untouched { ctx.note(String(localized: .noteImportRequirementsUntouched(name))) }

        try ctx.editCatalog { $0.categories = r.categories }
        try ctx.editTranscript { t in
            if let year = file.admissionYear { t.graduation.admissionYear = year }
            if let programs = file.programs {
                t.graduation.programs = programs.map {
                    StudentProgram(codeId: RequirementImporter.code($0.code, in: codes)!.id, kind: $0.kind)
                }
            }
        }
    }
}
