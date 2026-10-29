import ArgumentParser
import FolioDomain
import Foundation

extension RequirementCommand {
    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .requirementCheckAbstract), discussion: String(localized: .requirementCheckDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .requirementCheckHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String?
        @Option(help: ArgumentHelp(String(localized: .requirementCheckHelpOnly), valueName: "kind")) var only: [RequirementAudit.Kind] = []

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let catalog = try ctx.catalog().scoped(to: ctx.transcript().graduation.programs)
            guard let course else { return try all(r, catalog: catalog) }
            guard only.isEmpty else { throw CLIError(exit: .usage, message: String(localized: .requirementCheckOnlyWithoutCourse)) }
            let ref: CourseRef
            do {
                ref = try r.course(course)
            } catch let e as CLIError where e.exit == .notFound && e.candidates.isEmpty {
                return try code(course, catalog: catalog, notFound: e)
            }
            try one(ref, r, catalog: catalog)
        }

        struct Report: Encodable {
            struct Suggestion: Encodable { var course, title, code: String; var year: Int; var from, to: [String] }
            struct Shared: Encodable { var category: String; var cap, credits: Double; var courses: [String] }
            var suggestions: [Suggestion]
            var overShared: [Shared]
            var unallowed: [Shared]
            var unassigned: [String]
        }

        func all(_ r: Resolver, catalog: Catalog) throws {
            let refs = Dictionary(r.courses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let full = RequirementAudit(courses: r.courses.map(\.course), semesters: r.semesters, catalog: catalog)
            let audit = only.isEmpty ? full : full.keeping(Swift.Set(only))
            let names = { (ids: [UUID]) in ids.compactMap { catalog.category($0)?.name } }
            let tag = { (c: Course) in refs[c.id]?.code ?? c.title }
            let report = Report(
                suggestions: audit.suggestions.map { s in
                    let c = refs[s.courseId]
                    return .init(course: c?.code ?? "", title: c?.course.title ?? "", code: s.code, year: s.year, from: names(c?.course.categoryIds ?? []), to: names(s.categoryIds))
                },
                overShared: audit.overShared.map { .init(category: catalog.category($0.categoryId)?.name ?? "", cap: $0.cap, credits: $0.earned + $0.inProgress, courses: $0.courses.map(tag)) },
                unallowed: audit.unallowed.map { .init(category: catalog.category($0.categoryId)?.name ?? "", cap: $0.cap, credits: $0.unallowed.map(\.credits).reduce(0, +), courses: $0.unallowed.map(tag)) },
                unassigned: audit.unassigned.map(tag))
            if g.json {
                try printJSON(report)
            } else if audit.isEmpty {
                say("✓".styled(.green) + " " + String(localized: .requirementCheckNothing))
            } else {
                printReport(report, refs: refs)
            }
            if !audit.isEmpty { throw CLIError(exit: .rule, message: String(localized: .requirementCheckSomething)) }
        }

        func printReport(_ report: Report, refs: [UUID: CourseRef]) {
            let titles = Dictionary(refs.values.map { ($0.code, $0.course.title) }, uniquingKeysWith: { a, _ in a })
            func courses(_ codes: [String]) {
                var t = Table(header: [String(localized: .requirementCheckHeaderCode), String(localized: .requirementCheckHeaderCourse)], shrink: [1])
                t.rows = codes.map { [$0, titles[$0] ?? ""] }
                t.print()
            }
            if !report.suggestions.isEmpty {
                say(String(localized: .requirementCheckSuggestionsTitle(report.suggestions.count)).styled(.bold))
                var t = Table(header: [String(localized: .requirementCheckHeaderCode), String(localized: .requirementCheckHeaderCourse), String(localized: .requirementCheckHeaderHandbook), String(localized: .requirementCheckHeaderNow), String(localized: .requirementCheckHeaderHandbookCategories)], shrink: [1, 3])
                t.rows = report.suggestions.map { [$0.course, $0.title, "\($0.year) \($0.code)", $0.from.joined(separator: ", "), $0.to.joined(separator: ", ")] }
                t.print()
                say(String(localized: .requirementCheckSuggestionsHint).styled(.dim))
            }
            for s in report.overShared {
                say(String(localized: .requirementCheckOverSharedTitle(s.category, s.credits.formatted(), s.cap.formatted())).styled(.bold))
                courses(s.courses)
                say(String(localized: .requirementCheckOverSharedHint).styled(.dim))
            }
            for s in report.unallowed {
                say(String(localized: .requirementCheckUnallowedTitle(s.category, s.courses.count)).styled(.bold))
                courses(s.courses)
                say(String(localized: .requirementCheckUnallowedHint(s.category)).styled(.dim))
            }
            if !report.unassigned.isEmpty {
                say(String(localized: .requirementCheckUnassignedTitle(report.unassigned.count)).styled(.bold))
                courses(report.unassigned)
                say(String(localized: .requirementCheckUnassignedHint).styled(.dim))
            }
        }

        struct One: Encodable {
            struct Area: Encodable { var year: Int; var area: String }
            struct Sharing: Encodable { var category: String; var allowed: Bool; var reason: String }
            var course, title: String
            var categories: [String]
            var handbook: [Area]
            /// Categories the handbook of the year taken would give it, when they differ.
            var suggested: [String]?
            var sharing: [Sharing]
        }

        func one(_ ref: CourseRef, _ r: Resolver, catalog: Catalog) throws {
            let c = ref.course
            let year = c.semesterId.flatMap { id in r.semesters.first { $0.id == id }?.year }
            let number = c.number.split(separator: "-").first.map(String.init) ?? ""
            let codes = c.codes.compactMap { catalog.code($0)?.prefix }.map { $0 + number }
            let areas = codes.flatMap { HandbookClassifier.areas(of: $0, catalog: catalog) }.filter { $0.year == year }
            let suggestion = HandbookClassifier.suggest(courses: [c], semesters: r.semesters, catalog: catalog).first
            let sharing = GPACalculator.shared(courses: [c], catalog: catalog).map { s in
                let allowed = s.unallowed.isEmpty
                return One.Sharing(category: catalog.category(s.categoryId)?.name ?? "", allowed: allowed,
                                   reason: !allowed ? String(localized: .requirementCheckReasonNone) : c.sharingApproved == true ? String(localized: .requirementCheckReasonApproved) : String(localized: .requirementCheckReasonShared(codes.joined(separator: "/"))))
            }
            let one = One(course: ref.code, title: c.title, categories: c.categoryIds.compactMap { catalog.category($0)?.name },
                          handbook: areas.map { .init(year: $0.year, area: $0.area) },
                          suggested: suggestion.map { $0.categoryIds.compactMap { catalog.category($0)?.name } }, sharing: sharing)
            if g.json { return try printJSON(one) }
            courseHeader(ref, catalog: catalog)
            say(String(localized: .requirementCheckCategories(one.categories.isEmpty ? String(localized: .requirementCheckNone).styled(.yellow) : one.categories.joined(separator: ", "))))
            if let a = areas.first { say(String(localized: .requirementCheckHandbook(a.year, a.area))) }
            if let s = one.suggested { say(String(localized: .requirementCheckSuggestionLabel) + String(localized: .requirementCheckSuggestion(s.joined(separator: ", "))).styled(.yellow)) }
            for s in sharing {
                say(String(localized: .requirementCheckSharing(s.category)) + (s.allowed ? String(localized: .requirementCheckSharingAllowed(s.reason)) : String(localized: .requirementCheckSharingUnallowed(s.reason)).styled(.yellow)))
            }
        }

        /// A code no course has yet: only the handbook tables can say where it would go.
        func code(_ code: String, catalog: Catalog, notFound: CLIError) throws {
            let areas = HandbookClassifier.areas(of: code, catalog: catalog)
            guard !areas.isEmpty else { throw notFound }
            if g.json { return try printJSON(areas.map { One.Area(year: $0.year, area: $0.area) }) }
            say(code.uppercased().styled(.bold) + "  " + String(localized: .requirementCheckCodeOnly).styled(.dim))
            for a in areas { say(String(localized: .requirementCheckCodeArea(a.year, a.area))) }
        }
    }
}

extension RequirementAudit.Kind: ExpressibleByArgument {}
