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
        commandName: "score", abstract: "점수: 목록, 추가, 고치기, 지우기",
        subcommands: [List.self] + GeneratedCommands.score)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목의 점수 목록", discussion: """
            예시:
              folio score list EC4207
              folio score list EC4207 --lines
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = try c.requireFile()
            try GradesLock.require()
            let order = Dictionary(f.components.map { ($0.id, $0.order) }, uniquingKeysWith: { a, _ in a })
            let scores = f.scores.sorted { (order[$0.componentId] ?? 0, $0.date?.description ?? "") < (order[$1.componentId] ?? 0, $1.date?.description ?? "") }
            if g.json { return try printJSON(scores) }
            let name = { (s: ScoreEntry) in f.components.first { $0.id == s.componentId }?.name ?? "" }
            let points = { (s: ScoreEntry) in s.excused ? "면제" : "\(s.score.formatted())/\(s.max.formatted())" }
            if lines {
                for s in scores { line(["\(c.code)/\(s.title.isEmpty ? s.id.uuidString : s.title)", name(s), s.title, points(s)]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: ["항목", "제목", "점수", "날짜"], shrink: [1])
            for s in scores { t.rows.append([name(s), s.title, points(s), s.date?.description ?? ""]) }
            t.print()
            footer(scores.count)
        }
    }
}

struct ComponentCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "component", abstract: "성적 항목: 비중, 집계 방식, 순서, 성적 규칙",
        subcommands: [List.self] + GeneratedCommands.component + [Move.self, Policy.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목의 성적 항목과 비중", discussion: """
            예시:
              folio component list EC4207
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

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
            var t = Table(header: ["항목", "비중", "묶음", "집계", "점수"], shrink: [2])
            for x in components {
                let scores = f.scores.filter { $0.componentId == x.id }.count
                let count = x.expectedCount.map { "\(scores)/\($0)" } ?? "\(scores)"
                let aggregation = String(decoding: (try? JSONEncoder().encode(x.aggregation)) ?? Data(), as: UTF8.self).trimmingCharacters(in: ["\""])
                t.rows.append([x.name, bar(x.weight / 100).course(c.color) + " \(x.weight.formatted())%", x.group ?? "", aggregation, count])
            }
            t.print()
            let total = components.map(\.weight).reduce(0, +)
            footer(components.count, hidden: "비중 합계 \(total.formatted())%" + (components.isEmpty || total == 100 ? "" : " · 100%가 아닙니다"))
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "move", abstract: "성적 항목을 한 칸 위나 아래로", discussion: """
            예시:
              folio component move EC4207/퀴즈 --up
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<항목>", valueName: "item"), completion: Complete.components) var component: String = ""
        @Flag(help: "위로") var up = false
        @Flag(help: "아래로") var down = false

        func run() throws {
            guard up != down else { throw CLIError(exit: .usage, message: "--up과 --down 중 하나를 주세요") }
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, ref) = try r.split(component)
            let x = try r.component(ref, in: c)
            try perform(spec: ComponentMove(course: c.id, component: x.id, by: up ? -1 : 1), g, ctx: ctx)
        }
    }

    struct Policy: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "policy", abstract: "성적 규칙 바꾸기. 준 것만 바꾼다", discussion: """
            예시:
              folio component policy EC4207 --min-attendance-ratio 0.75 --lates-per-absence 3
              folio component policy EC4207 --notes "Quiz 최저 점수 1회 제외"
              folio component policy EC4207 --cap 6:B0 --cap 9:F
              folio component policy EC4207 --cutoff A+:95 --cutoff A0:90 --top-grade-ratio none --dry-run

            값을 지우려면 none을 준다. --cap과 --cutoff는 주면 기존 목록을 바꾸고, none이면 비운다.
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Option(help: "최소 출석 비율. 0.75") var minAttendanceRatio: Clearable<Double>?
        @Option(help: "지각 규칙 설명") var latePolicy: Clearable<String>?
        @Option(help: "지각 몇 번이 결석 한 번인지") var latesPerAbsence: Clearable<Int>?
        @Option(help: "상대평가에서 A를 받는 비율. 0.5") var topGradeRatio: Clearable<Double>?
        @Option(help: ArgumentHelp("결석 횟수:최대 성적. 6:B0. 여러 번 줄 수 있다", valueName: "cap")) var cap: [String] = []
        @Option(help: ArgumentHelp("성적:최저 점수. A+:95. 여러 번 줄 수 있다", valueName: "cutoff")) var cutoff: [String] = []
        @Option(help: "구조로 옮기지 못한 규칙 원문") var notes: String?

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
                guard let i = s.lastIndex(of: ":") else { throw CLIError(exit: .usage, message: "<왼쪽>:<오른쪽> 꼴로 주세요: \(s)") }
                return (String(s[..<i]), String(s[s.index(after: i)...]))
            }
            if !cap.isEmpty {
                p.attendanceCap = try cap.clearing.map { s in
                    let (n, grade) = try pair(s)
                    guard let absences = Int(n) else { throw CLIError(exit: .usage, message: "결석 횟수는 정수로 주세요: \(s)") }
                    return AttendanceCap(absences: absences, maxGrade: try r.letterGrade(grade).id)
                }
            }
            if !cutoff.isEmpty {
                p.cutoffs = try cutoff.clearing.map { s in
                    let (grade, n) = try pair(s)
                    guard let min = Double(n) else { throw CLIError(exit: .usage, message: "최저 점수는 숫자로 주세요: \(s)") }
                    return GradeCutoff(grade: try r.letterGrade(grade).id, minScore: min)
                }
            }
            try perform(spec: PolicySet(course: c.id, policy: p), g, ctx: ctx)
        }
    }
}

struct GPACommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "gpa", abstract: "학기별 학점과 GPA, 누적과 전공", discussion: """
        예시:
          folio gpa
          folio gpa --json
        """)
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
        let rows = semesters.map { row($0.folder?.name ?? "인정학기", GPACalculator.semester($0, courses: courses, catalog: catalog)) }
            + [row("누적", GPACalculator.cumulative(semesters: semesters, courses: courses, catalog: catalog)),
               row("전공", GPACalculator.major(courses: courses, catalog: catalog))]
        if g.json { return try printJSON(rows) }
        var t = Table(header: ["학기", "총 학점", "유효 학점", "GPA"])
        for (i, x) in rows.enumerated() {
            let cells = [x.name, x.totalCredits.formatted(), x.effectiveCredits.formatted(), GPACalculator.label(x.gpa)]
            t.rows.append(i >= semesters.count ? cells.map { $0.styled(.bold) } : cells)
        }
        t.print()
    }
}

struct RequirementCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "requirement", abstract: "졸업 요건과 학생 정보", subcommands: [Show.self, Set.self, Check.self])

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "졸업 요건과 학생 정보 보기", discussion: """
            예시:
              folio requirement show
            """)
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let ctx = try CLI.context(g)
            let rule = try ctx.transcript().graduation
            if g.json { return try printJSON(rule) }
            let codes = (try? ctx.catalog().codes) ?? []
            say("졸업 요건".styled(.bold))
            say("  졸업 학점  \(rule.totalCredits.formatted())")
            say("  최저 평점  \(rule.minGPA.formatted())")
            say("  입학 연도  \(rule.admissionYear.map(String.init) ?? "-")")
            if !rule.email.isEmpty { say("  메일  \(rule.email)") }
            if !rule.programs.isEmpty {
                say("  전공")
                for p in rule.programs { say("    \(p.kind.rawValue)  \(codes.first { $0.id == p.codeId }?.prefix ?? p.codeId.uuidString)") }
            }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "졸업 요건과 학생 정보 바꾸기. 준 것만 바꾼다", discussion: """
            예시:
              folio requirement set --admission-year 2023
              folio requirement set --total-credits 130 --min-gpa 2.0
              folio requirement set --program major:EC --program minor:GS --dry-run

            --program은 주면 기존 목록을 바꾸고, none이면 비운다. 과정은 major, doubleMajor, minor, intensive.
            """)
        @OptionGroup var g: GlobalOptions
        @Option(help: "졸업 학점") var totalCredits: Double?
        @Option(help: "최저 평점") var minGPA: Double?
        @Option(help: "입학 연도(학번). none이면 지운다") var admissionYear: Clearable<Int>?
        @Option(help: "교수에게 메일을 보낼 계정") var email: String?
        @Option(help: ArgumentHelp("과정:강의 코드 앞부분. major:EC. 여러 번 줄 수 있다", valueName: "program")) var program: [String] = []

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
                        throw CLIError(exit: .usage, message: "<과정>:<강의 코드 앞부분> 꼴로 주세요: \(s)", hints: ["과정: " + StudentProgram.Kind.allCases.map(\.rawValue).joined(separator: ", ")])
                    }
                    guard let code = codes.first(where: { $0.prefix.caseInsensitiveCompare(parts[1]) == .orderedSame }) else {
                        throw CLIError(exit: .notFound, message: "강의 코드를 찾지 못했습니다: \(parts[1])", candidates: codes.map(\.prefix))
                    }
                    return StudentProgram(codeId: code.id, kind: kind)
                }
            }
            try perform(spec: GraduationSet(rule: rule), g, ctx: ctx)
        }
    }
}
