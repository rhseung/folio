import FolioActions
import FolioDomain
import Foundation

extension RequirementShow: QueryOutput {
    func say(_ rule: GraduationRule, _ r: Resolver) throws {
        let codes = (try? r.ctx.catalog().codes) ?? []
        FolioCLI.say(String(localized: .requirementShowTitle).styled(.bold))
        FolioCLI.say(String(localized: .requirementShowTotalCredits(rule.totalCredits.formatted())))
        FolioCLI.say(String(localized: .requirementShowMinGpa(rule.minGPA.formatted())))
        FolioCLI.say(String(localized: .requirementShowAdmissionYear(rule.admissionYear.map(String.init) ?? "-")))
        if !rule.email.isEmpty { FolioCLI.say(String(localized: .requirementShowEmail(rule.email))) }
        if !rule.programs.isEmpty {
            FolioCLI.say(String(localized: .requirementShowPrograms))
            for p in rule.programs {
                FolioCLI.say("    \(p.kind.rawValue)  \(codes.first { $0.id == p.codeId }?.prefix ?? p.codeId.uuidString)")
            }
        }
    }
}
