import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension Resolver {
    /// A score by its title or id; several scores often share a component, so titles are what tell them apart.
    func score(_ name: String, in c: CourseRef) throws -> ScoreEntry {
        let f = try c.requireFile()
        // An untitled score shows as its component's name, so it is found by that name too.
        return try pick(name, f.scores, what: "점수", names: { [f.name(of: $0.id) ?? $0.title] }, ref: { "\(c.code)/\($0.title.isEmpty ? $0.id.uuidString : $0.title)" })
    }

    func letterGrade(_ symbol: String) throws -> LetterGrade {
        try pick(symbol, try ctx.catalog().letterGrades, what: "성적", names: { [$0.symbol] }, ref: \.symbol)
    }
}

/// `sum`, `mean`, `single`, `dropLowest:1`, `bestOf:3`, read the way course.json stores them.
extension Aggregation: ExpressibleByArgument {
    public init?(argument: String) {
        guard let v = try? JSONDecoder().decode(Aggregation.self, from: Data("\"\(argument)\"".utf8)) else { return nil }
        self = v
    }
    public static var allValueStrings: [String] { ["sum", "mean", "single", "dropLowest:<n>", "bestOf:<n>"] }
}

/// `█████░░░░░ 50%`: the number next to the bar keeps it readable without color.
func bar(_ fraction: Double, width: Int = 10) -> String {
    let filled = Int((min(max(fraction, 0), 1) * Double(width)).rounded())
    return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
}

struct ScoreCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "score", abstract: String(localized: .scoreAbstract),
        subcommands: [List.self] + GeneratedCommands.score)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .scoreListAbstract), discussion: String(localized: .scoreListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = try c.requireFile()
            try GradesLock.require()
            let order = Dictionary(f.components.map { ($0.id, $0.order) }, uniquingKeysWith: { a, _ in a })
            let scores = f.scores.sorted { (order[$0.componentId] ?? 0, $0.date?.description ?? "") < (order[$1.componentId] ?? 0, $1.date?.description ?? "") }
            if g.json { return try printJSON(scores) }
            let name = { (s: ScoreEntry) in f.components.first { $0.id == s.componentId }?.name ?? "" }
            let points = { (s: ScoreEntry) in s.excused ? String(localized: .scoreListExcused) : "\(s.score.formatted())/\(s.max.formatted())" }
            if lines {
                for s in scores { line(["\(c.code)/\(s.title.isEmpty ? s.id.uuidString : s.title)", name(s), s.title, points(s)]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: [String(localized: .scoreListHeaderComponent), String(localized: .scoreListHeaderTitle), String(localized: .scoreListHeaderScore), String(localized: .scoreListHeaderDate)], shrink: [1])
            for s in scores { t.rows.append([name(s), s.title, points(s), s.date?.description ?? ""]) }
            t.print()
            footer(scores.count)
        }
    }
}

struct ComponentCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "component", abstract: String(localized: .componentAbstract),
        subcommands: [List.self] + GeneratedCommands.component + [Move.self, Policy.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .componentListAbstract), discussion: String(localized: .componentListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = try c.requireFile()
            let components = f.components.sorted { $0.order < $1.order }
            if g.json { return try printJSON(components) }
            if lines {
                for x in components { line(["\(c.code)/\(x.name)", "\(x.weight.formatted())%", x.group ?? ""]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: [String(localized: .componentListHeaderComponent), String(localized: .componentListHeaderWeight), String(localized: .componentListHeaderGroup), String(localized: .componentListHeaderAggregation), String(localized: .componentListHeaderScores)], shrink: [2])
            for x in components {
                let scores = f.scores.filter { $0.componentId == x.id }.count
                let count = x.expectedCount.map { "\(scores)/\($0)" } ?? "\(scores)"
                let aggregation = String(decoding: (try? JSONEncoder().encode(x.aggregation)) ?? Data(), as: UTF8.self).trimmingCharacters(in: ["\""])
                t.rows.append([x.name, bar(x.weight / 100).course(c.color) + " \(x.weight.formatted())%", x.group ?? "", aggregation, count])
            }
            t.print()
            let total = components.map(\.weight).reduce(0, +)
            footer(components.count, hidden: String(localized: components.isEmpty || total == 100 ? .componentListTotal(total.formatted()) : .componentListTotalOff(total.formatted())))
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "move", abstract: String(localized: .componentMoveAbstract), discussion: String(localized: .componentMoveDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .componentMoveHelpComponent), valueName: "item"), completion: Complete.components) var component: String = ""
        @Flag(help: ArgumentHelp(String(localized: .componentMoveHelpUp))) var up = false
        @Flag(help: ArgumentHelp(String(localized: .componentMoveHelpDown))) var down = false

        func run() throws {
            guard up != down else { throw CLIError(exit: .usage, message: String(localized: .componentMoveUpOrDown)) }
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, ref) = try r.split(component)
            let x = try r.component(ref, in: c)
            try perform(spec: ComponentMove(course: c.id, component: x.id, by: up ? -1 : 1), g, ctx: ctx)
        }
    }

    struct Policy: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "policy", abstract: String(localized: .componentPolicyAbstract), discussion: String(localized: .componentPolicyDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Option(help: ArgumentHelp(String(localized: .componentPolicyHelpMinAttendanceRatio))) var minAttendanceRatio: Clearable<Double>?
        @Option(help: ArgumentHelp(String(localized: .componentPolicyHelpLatePolicy))) var latePolicy: Clearable<String>?
        @Option(help: ArgumentHelp(String(localized: .componentPolicyHelpLatesPerAbsence))) var latesPerAbsence: Clearable<Int>?
        @Option(help: ArgumentHelp(String(localized: .componentPolicyHelpTopGradeRatio))) var topGradeRatio: Clearable<Double>?
        @Option(help: ArgumentHelp(String(localized: .componentPolicyHelpCap), valueName: "cap")) var cap: [String] = []
        @Option(help: ArgumentHelp(String(localized: .componentPolicyHelpCutoff), valueName: "cutoff")) var cutoff: [String] = []
        @Option(help: ArgumentHelp(String(localized: .componentPolicyHelpNotes))) var notes: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let c = try r.course(course)
            var p = try c.requireFile().policy
            if let minAttendanceRatio { p.minAttendanceRatio = minAttendanceRatio.value }
            if let latePolicy { p.latePolicy = latePolicy.value }
            if let latesPerAbsence { p.latesPerAbsence = latesPerAbsence.value }
            if let topGradeRatio { p.topGradeRatio = topGradeRatio.value }
            if let notes { p.notes = notes }
            /// `6:B0`, `A+:95`: the left side before the last colon, read as `T`; the right side a letter grade or score.
            func pair(_ s: String) throws -> (String, String) {
                guard let i = s.lastIndex(of: ":") else { throw CLIError(exit: .usage, message: String(localized: .componentPolicyBadPair(s))) }
                return (String(s[..<i]), String(s[s.index(after: i)...]))
            }
            if !cap.isEmpty {
                p.attendanceCap = try cap.clearing.map { s in
                    let (n, grade) = try pair(s)
                    guard let absences = Int(n) else { throw CLIError(exit: .usage, message: String(localized: .componentPolicyBadAbsences(s))) }
                    return AttendanceCap(absences: absences, maxGrade: try r.letterGrade(grade).id)
                }
            }
            if !cutoff.isEmpty {
                p.cutoffs = try cutoff.clearing.map { s in
                    let (grade, n) = try pair(s)
                    guard let min = Double(n) else { throw CLIError(exit: .usage, message: String(localized: .componentPolicyBadMinScore(s))) }
                    return GradeCutoff(grade: try r.letterGrade(grade).id, minScore: min)
                }
            }
            try perform(spec: PolicySet(course: c.id, policy: p), g, ctx: ctx)
        }
    }
}

struct GPACommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "gpa", abstract: String(localized: .gpaAbstract), discussion: String(localized: .gpaDiscussion))
    @OptionGroup var g: GlobalOptions

    struct Row: Encodable {
        var name: String
        var totalCredits: Double
        var effectiveCredits: Double
        var gpa: Double?
    }

    func run() throws {
        let ctx = try CLI.context(g)
        try GradesLock.require()
        let catalog = try ctx.catalog()
        let courses = try ctx.gist.allCourses()
        let semesters = try ctx.transcript().semesters.sorted { $0.order < $1.order }
        let row = { (name: String, s: GPACalculator.Summary) in Row(name: name, totalCredits: s.totalCredits, effectiveCredits: s.effectiveCredits, gpa: s.gpa) }
        let rows = semesters.map { row($0.folder?.name ?? String(localized: .semesterRecognized), GPACalculator.semester($0, courses: courses, catalog: catalog)) }
            + [row(String(localized: .gpaCumulative), GPACalculator.cumulative(semesters: semesters, courses: courses, catalog: catalog)),
               row(String(localized: .gpaMajor), GPACalculator.major(courses: courses, catalog: catalog))]
        if g.json { return try printJSON(rows) }
        var t = Table(header: [String(localized: .gpaHeaderSemester), String(localized: .gpaHeaderTotalCredits), String(localized: .gpaHeaderEffectiveCredits), "GPA"])
        for (i, x) in rows.enumerated() {
            let cells = [x.name, x.totalCredits.formatted(), x.effectiveCredits.formatted(), GPACalculator.label(x.gpa)]
            t.rows.append(i >= semesters.count ? cells.map { $0.styled(.bold) } : cells)
        }
        t.print()
    }
}

struct RequirementCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "requirement", abstract: String(localized: .requirementAbstract), subcommands: [Show.self, Set.self, Check.self])

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .requirementShowAbstract), discussion: String(localized: .requirementShowDiscussion))
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
                for p in rule.programs { say("    \(p.kind.rawValue)  \(codes.first { $0.id == p.codeId }?.prefix ?? p.codeId.uuidString)") }
            }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .requirementSetAbstract), discussion: String(localized: .requirementSetDiscussion))
        @OptionGroup var g: GlobalOptions
        @Option(help: ArgumentHelp(String(localized: .requirementSetHelpTotalCredits))) var totalCredits: Double?
        @Option(help: ArgumentHelp(String(localized: .requirementSetHelpMinGpa))) var minGPA: Double?
        @Option(help: ArgumentHelp(String(localized: .requirementSetHelpAdmissionYear))) var admissionYear: Clearable<Int>?
        @Option(help: ArgumentHelp(String(localized: .requirementSetHelpEmail))) var email: String?
        @Option(help: ArgumentHelp(String(localized: .requirementSetHelpProgram), valueName: "program")) var program: [String] = []

        func run() throws {
            let ctx = try CLI.context(g)
            var rule = try ctx.transcript().graduation
            if let totalCredits { rule.totalCredits = totalCredits }
            if let minGPA { rule.minGPA = minGPA }
            if let admissionYear { rule.admissionYear = admissionYear.value }
            if let email { rule.email = email }
            if !program.isEmpty {
                let codes = try ctx.catalog().codes
                rule.programs = try program.clearing.map { s in
                    let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
                    guard parts.count == 2, let kind = StudentProgram.Kind(rawValue: parts[0]) else {
                        throw CLIError(exit: .usage, message: String(localized: .requirementSetBadProgram(s)), hints: [String(localized: .requirementSetProgramKinds) + StudentProgram.Kind.allCases.map(\.rawValue).joined(separator: ", ")])
                    }
                    guard let code = codes.first(where: { $0.prefix.caseInsensitiveCompare(parts[1]) == .orderedSame }) else {
                        throw CLIError(exit: .notFound, message: String(localized: .requirementSetUnknownCode(parts[1])), candidates: codes.map(\.prefix))
                    }
                    return StudentProgram(codeId: code.id, kind: kind)
                }
            }
            try perform(spec: GraduationSet(rule: rule), g, ctx: ctx)
        }
    }
}
