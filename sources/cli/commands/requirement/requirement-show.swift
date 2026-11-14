import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension RequirementCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .requirementShowAbstract), discussion: String(localized: .requirementShowDiscussion))
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let ctx = try CLI.context(g)
            let rule = try ctx.transcript().graduation
            if g.json { return try printJSON(rule) }
            let codes = (try? ctx.catalog().codes) ?? []
            say(String(localized: .requirementShowTitle).styled(.bold))
            say(String(localized: .requirementShowTotalCredits(rule.totalCredits.formatted())))
            say(String(localized: .requirementShowMinGpa(rule.minGPA.formatted())))
            say(String(localized: .requirementShowAdmissionYear(rule.admissionYear.map(String.init) ?? "-")))
            if !rule.email.isEmpty { say(String(localized: .requirementShowEmail(rule.email))) }
            if !rule.programs.isEmpty {
                say(String(localized: .requirementShowPrograms))
                for p in rule.programs {
                    say("    \(p.kind.rawValue)  \(codes.first { $0.id == p.codeId }?.prefix ?? p.codeId.uuidString)")
                }
            }
        }
    }
}
