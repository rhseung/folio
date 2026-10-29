import ArgumentParser
import FolioDomain
import Foundation

extension RequirementCommand {
    /// The requirements page's decision cards, from the same RequirementAudit the app draws.
    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "졸업 요건에서 정할 것: 편람과 다른 분류, 이중 계산, 분류 없는 과목", discussion: """
            과목 인자를 빼면 졸업 요건 화면의 알림을 모두 보여 준다. 정할 것이 있으면 종료 코드 4로 끝나고, 없으면 0이다.
            --only로 판정을 고르면 그 판정만 보고 종료 코드도 그것으로 정한다.
            과목을 주면 그 과목의 분류, 그해 학사편람의 분류, 이중 계산 여부를 보여 준다.
            아직 듣지 않은 강의 코드(HS2734)를 주면 학사편람 분류 표에서 찾는다.

            예시:
              folio requirement check EC4207
              folio requirement check EC4207 --json
              folio requirement check --only handbook --only shared
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목이나 강의 코드. 빼면 모든 과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String?
        @Option(help: ArgumentHelp("""
            이 판정만 본다. 여러 번 주면 모두. handbook 편람과 다른 분류, shared 이중 계산 상한 초과, \
            unallowed 두 과정에 함께 셀 수 없는 과목, unassigned 분류 없는 과목
            """, valueName: "kind")) var only: [RequirementAudit.Kind] = []

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let catalog = try ctx.catalog().scoped(to: ctx.transcript().graduation.programs)
            guard let course else { return try all(r, catalog: catalog) }
            guard only.isEmpty else { throw CLIError(exit: .usage, message: "--only는 과목 없이 쓸 때만 받습니다") }
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
                say("✓".styled(.green) + " 졸업 요건에서 정할 것이 없습니다")
            } else {
                printReport(report, refs: refs)
            }
            if !audit.isEmpty { throw CLIError(exit: .rule, message: "졸업 요건에서 정할 것이 있습니다") }
        }

        func printReport(_ report: Report, refs: [UUID: CourseRef]) {
            let titles = Dictionary(refs.values.map { ($0.code, $0.course.title) }, uniquingKeysWith: { a, _ in a })
            func courses(_ codes: [String]) {
                var t = Table(header: ["코드", "과목"], shrink: [1])
                t.rows = codes.map { [$0, titles[$0] ?? ""] }
                t.print()
            }
            if !report.suggestions.isEmpty {
                say("학사편람과 분류가 다른 과목 \(report.suggestions.count)개".styled(.bold))
                var t = Table(header: ["코드", "과목", "편람", "지금", "편람 분류"], shrink: [1, 3])
                t.rows = report.suggestions.map { [$0.course, $0.title, "\($0.year) \($0.code)", $0.from.joined(separator: ", "), $0.to.joined(separator: ", ")] }
                t.print()
                say("  folio import handbook <파일> --accept로 모두 적용하거나, folio course set <과목> --category로 하나씩 고칩니다".styled(.dim))
            }
            for s in report.overShared {
                say("‘\(s.category)’ 이중 계산 \(s.credits.formatted())학점 중 \(s.cap.formatted())학점만 인정".styled(.bold))
                courses(s.courses)
                say("  이중 계산하지 않을 과목을 folio course set <과목> --category로 한쪽 분류에서 뺍니다".styled(.dim))
            }
            for s in report.unallowed {
                say("‘\(s.category)’에 함께 셀 수 없는 과목 \(s.courses.count)개".styled(.bold))
                courses(s.courses)
                say("  강의 공유도 학과 인정도 아니어서 \(s.category)에서 빼고 셉니다. 학과 인정 과목이면 folio course set <과목> --sharing-approved true".styled(.dim))
            }
            if !report.unassigned.isEmpty {
                say("분류 없는 과목 \(report.unassigned.count)개".styled(.bold))
                courses(report.unassigned)
                say("  folio course set <과목> --category <분류>".styled(.dim))
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
                                   reason: !allowed ? "강의 공유도 학과 인정도 아님" : c.sharingApproved == true ? "학과 인정" : "강의 공유 \(codes.joined(separator: "/"))")
            }
            let one = One(course: ref.code, title: c.title, categories: c.categoryIds.compactMap { catalog.category($0)?.name },
                          handbook: areas.map { .init(year: $0.year, area: $0.area) },
                          suggested: suggestion.map { $0.categoryIds.compactMap { catalog.category($0)?.name } }, sharing: sharing)
            if g.json { return try printJSON(one) }
            courseHeader(ref, catalog: catalog)
            say("  분류  \(one.categories.isEmpty ? "없음".styled(.yellow) : one.categories.joined(separator: ", "))")
            if let a = areas.first { say("  편람  \(a.year) \(a.area)") }
            if let s = one.suggested { say("  제안  " + "\(s.joined(separator: ", "))로 바꾸기".styled(.yellow)) }
            for s in sharing {
                say("  이중 계산  \(s.category): " + (s.allowed ? "함께 셈 (\(s.reason))" : "함께 셀 수 없음 (\(s.reason))".styled(.yellow)))
            }
        }

        /// A code no course has yet: only the handbook tables can say where it would go.
        func code(_ code: String, catalog: Catalog, notFound: CLIError) throws {
            let areas = HandbookClassifier.areas(of: code, catalog: catalog)
            guard !areas.isEmpty else { throw notFound }
            if g.json { return try printJSON(areas.map { One.Area(year: $0.year, area: $0.area) }) }
            say(code.uppercased().styled(.bold) + "  " + "들은 과목이 아니라 학사편람 분류만 찾았습니다".styled(.dim))
            for a in areas { say("  \(a.year) 편람  \(a.area)") }
        }
    }
}

extension RequirementAudit.Kind: ExpressibleByArgument {}
