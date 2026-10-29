import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Resolver {
    func code(_ prefix: String) throws -> CourseCode {
        try pick(prefix, try ctx.catalog().codes, what: "강의 코드", names: { [$0.prefix] }, ref: \.prefix)
    }

    func person(_ name: String) throws -> Person {
        try pick(name, try ctx.catalog().people, what: "교수", names: { [$0.name] }, ref: \.name)
    }

    func category(_ name: String) throws -> FolioDomain.Category {
        try pick(name, try ctx.catalog().categories, what: "분류", names: { [$0.name] }, ref: \.name)
    }
}

/// A whole document read from a JSON file, for the catalog and settings that the app edits as one form.
func readJSON<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
    let url = URL(filePath: (path as NSString).expandingTildeInPath)
    guard let data = try? Data(contentsOf: url) else { throw CLIError(exit: .usage, message: "파일을 읽지 못했습니다: \(path)") }
    do {
        return try JSONDecoder.folio.decode(T.self, from: data)
    } catch let e as DecodingError {
        throw CLIError(exit: .usage, message: "파일이 맞지 않습니다: \(RunCommand.describe(e))")
    }
}

struct SemesterCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "semester", abstract: "학기: 목록, 추가, 기간과 시험 주차",
        subcommands: [List.self, Show.self] + GeneratedCommands.semester)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "학기 목록", discussion: """
            예시:
              folio semester list
            """)
        @OptionGroup var g: GlobalOptions
        @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let semesters = r.semesters
            if g.json { return try printJSON(semesters) }
            let span = { (s: Semester) in [s.start?.description, s.end?.description].map { $0 ?? "?" }.joined(separator: " – ") }
            if lines {
                for s in semesters { line([s.folder?.name ?? s.id.uuidString, "\(s.year) \(s.term.rawValue)", span(s)]) }
                return
            }
            let current = try? r.currentSemester().id
            var t = Table(header: ["학기", "이름", "기간"])
            for s in semesters {
                let cells = [s.folder?.name ?? "인정학기", "\(s.year) \(s.term.rawValue)", span(s)]
                t.rows.append(s.id == current ? cells.map { $0.styled(.bold) } : cells)
            }
            t.print()
            footer(semesters.count)
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "학기 하나. 생략하면 현재 학기", discussion: """
            예시:
              folio semester show
              folio semester show 2026-1
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("학기. 2026-3 또는 \"2026 fall\"", valueName: "semester"), completion: .custom(Complete.semesters)) var semester: String?

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let s = try r.semester(semester)
            if g.json { return try printJSON(s) }
            say((s.folder?.name ?? "인정학기").styled(.bold) + "  \(s.year) \(s.term.rawValue)".styled(.dim))
            say("  시작  \(s.start?.description ?? "-")")
            say("  끝  \(s.end?.description ?? "-")")
            if let w = s.midtermWeek { say("  중간고사  \(w)주차") }
            if let w = s.finalWeek { say("  기말고사  \(w)주차") }
            let courses = r.courses.filter { $0.course.semesterId == s.id }
            if !courses.isEmpty {
                say("  과목")
                for c in courses { say("    " + "●".course(c.color) + " \(c.tag) \(c.course.title)") }
            }
        }
    }
}

struct CourseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "course", abstract: "과목: 목록, 추가, 이름 바꾸기, 학점·평가 방식·색",
        subcommands: [List.self, Show.self, Add.self, Rename.self, Set.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목 목록. 생략하면 현재 학기", discussion: """
            예시:
              folio course list
              folio course list --semester 2026-1
              folio course list --all --lines
            """)
        @OptionGroup var g: GlobalOptions
        @Option(help: ArgumentHelp("학기", valueName: "semester"), completion: .custom(Complete.semesters)) var semester: String?
        @Flag(help: "모든 학기") var all = false
        @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let semesterId = all ? nil : try r.semester(semester).id
            let courses = r.courses.filter { semesterId == nil || $0.course.semesterId == semesterId }
            if g.json { return try printJSON(courses.map(\.course)) }
            if lines {
                for c in courses { line([c.code, c.course.title, "\(c.course.credits.formatted())학점"]) }
                return
            }
            let catalog = try? r.ctx.catalog()
            var t = Table(header: ["", "코드", "과목", "학점", "평가", "성적"], shrink: [2])
            for c in courses {
                t.rows.append(["●".course(c.color), c.tag, c.course.title, c.course.credits.formatted(), c.course.gradingMode.rawValue.toned,
                               catalog?.grade(c.course.finalGrade).map { GradesLock.masked($0.symbol) } ?? ""])
            }
            t.print()
            footer(courses.count, hidden: all ? nil : "--all로 모든 학기")
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목 하나의 자세한 내용", discussion: """
            예시:
              folio course show EC4207
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            if g.json { return try printJSON(c.course) }
            let catalog = try? r.ctx.catalog()
            courseHeader(c, catalog: catalog)
            let x = c.course
            say("  학점  \(x.credits.formatted())")
            say("  평가  \(x.gradingMode.rawValue)")
            if let grade = catalog?.grade(x.finalGrade) { say("  성적  \(GradesLock.masked(grade.symbol))") }
            let categories = x.categoryIds.compactMap { catalog?.category($0)?.name }
            if !categories.isEmpty { say("  분류  \(categories.joined(separator: ", "))") }
            if x.reviews == false { say("  복습  끔") }
            if !x.schedule.isEmpty {
                say("  시간표")
                for t in x.schedule {
                    say("    \(ClassTime.weekdayNames[t.weekday - 1]) \(String(format: "%02d:%02d–%02d:%02d", t.startMinute / 60, t.startMinute % 60, t.endMinute / 60, t.endMinute % 60)) \(t.room)")
                }
            }
            if x.sharingApproved == true { say("  학과 인정  전공과 복수전공에 함께 셈") }
            if !x.memo.isEmpty { say("  메모  \(x.memo)") }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목 추가. 과목 폴더와 course.json을 만든다", discussion: """
            강의 코드는 catalog.json에 있어야 한다. 폴더 이름은 `<코드><번호> <과목 이름>`이다.

            예시:
              folio course add EC 3101 "자료 구조" --credits 3
              folio course add GS 2004-02 "전공 글쓰기" --mode pass_fail --semester 2026-3 --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("강의 코드 앞부분. EC", valueName: "code")) var code: String
        @Argument(help: ArgumentHelp("일련번호. 4207-01", valueName: "number")) var number: String
        @Argument(help: ArgumentHelp("과목 이름", valueName: "name")) var title: String
        @Option(help: "학점") var credits: Double = 3
        @Option(help: "평가 방식") var mode: GradingMode = .relative
        @Option(help: ArgumentHelp("학기. 생략하면 현재 학기", valueName: "semester"), completion: .custom(Complete.semesters)) var semester: String?
        @Option(help: .hidden) var id: UUID?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            try perform(spec: CourseAdd(id: id ?? UUID(), semester: try r.semester(semester).id, title: title, code: try r.code(code).id, number: number,
                                        credits: credits, mode: mode), g, ctx: ctx)
        }
    }

    struct Rename: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목 이름, 코드, 번호 바꾸기. 폴더 이름도 바뀌므로 확인을 받는다", discussion: """
            폴더 이동은 .folio/moves.jsonl에 남아 `folio cleanup undo`로 되돌릴 수 있다.

            예시:
              folio course rename EC4207 --title "그래프 이론과 응용" --dry-run
              folio course rename EC4207 --number 4207-02
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Option(help: "과목 이름") var title: String?
        @Option(help: ArgumentHelp("강의 코드 앞부분. 여러 개면 첫째가 주 코드", valueName: "code")) var code: [String] = []
        @Option(help: "일련번호") var number: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let c = try r.course(course)
            let codes = code.isEmpty ? c.course.codes : try code.map { try r.code($0).id }
            try perform(spec: CourseRename(course: c.id, title: title ?? c.course.title, codes: codes, number: number ?? c.course.number), g, ctx: ctx)
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목의 학점, 평가 방식, 색, 아이콘, 성적, 교수, 분류, 학과 인정 바꾸기. 준 것만 바꾼다", discussion: """
            예시:
              folio course set EC4207 --color "#3A7BD5" --credits 3
              folio course set EC4207 --icon point.3.filled.connected.trianglepath.dotted
              folio course set EC4207 --grade A+ --instructor 김교수
              folio course set EC4207 --reviews false
              folio course set EC4207 --sharing-approved true
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Option(help: "메모") var memo: String?
        @Option(help: "학점") var credits: Double?
        @Option(help: "평가 방식") var mode: GradingMode?
        @Option(help: ArgumentHelp("강조색 #RRGGBB", valueName: "color")) var color: String?
        @Option(help: ArgumentHelp("앱에서 과목을 나타낼 SF Symbol 이름. none이면 지워 기본 아이콘(책)으로 돌린다", valueName: "symbol")) var icon: String?
        @Option(help: "복습 대상인지") var reviews: Toggle?
        @Option(help: "학과 인정 과목인지. 강의 공유 코드가 없어도 전공과 복수전공에 함께 셀 수 있다") var sharingApproved: Toggle?
        @Option(help: ArgumentHelp("최종 성적 기호. none이면 지운다", valueName: "grade")) var grade: String?
        @Option(help: ArgumentHelp("교수 이름. 여러 번 주면 모두. 주면 기존 목록을 바꾸고, none이면 비운다", valueName: "name")) var instructor: [String] = []
        @Option(help: ArgumentHelp("졸업 요건 분류 이름. 여러 번 주면 모두. 주면 기존 목록을 바꾸고, none이면 비운다", valueName: "category")) var category: [String] = []

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let c = try r.course(course)
            var fields: [CourseSet.Field] = []
            if let memo { fields.append(.memo(memo)) }
            if let credits { fields.append(.credits(credits)) }
            if let mode { fields.append(.gradingMode(mode)) }
            if let color { fields.append(.color(color)) }
            if let icon { fields.append(.icon(icon == "none" ? nil : icon)) }
            if let reviews { fields.append(.reviews(reviews.value)) }
            if let sharingApproved { fields.append(.sharingApproved(sharingApproved.value)) }
            if let grade { fields.append(.finalGrade(grade == "none" ? nil : try r.letterGrade(grade).id)) }
            if !instructor.isEmpty { fields.append(.instructors(try instructor.clearing.map { try r.person($0).id })) }
            if !category.isEmpty { fields.append(.categories(try category.clearing.map { try r.category($0).id })) }
            guard !fields.isEmpty else { throw CLIError(exit: .usage, message: "바꿀 것을 하나 이상 주세요") }
            try perform(spec: CourseSet(course: c.id, fields), g, ctx: ctx)
        }
    }
}

struct CatalogCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "catalog", abstract: "catalog.json: 강의 코드, 분류, 평어, 교수", subcommands: [Show.self, Set.self])

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "카탈로그 요약. --json이면 catalog.json 전체", discussion: """
            예시:
              folio catalog show
              folio catalog show --json > catalog.json
            """)
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let catalog = try CLI.context(g).catalog()
            if g.json { return try printJSON(catalog) }
            say("강의 코드".styled(.bold) + "  " + catalog.codes.map(\.prefix).joined(separator: " "))
            say("평어".styled(.bold) + "  " + catalog.letterGrades.map(\.symbol).joined(separator: " "))
            say("분류".styled(.bold) + "  \(catalog.categories.count)개")
            say("교수".styled(.bold) + "  " + catalog.people.map(\.name).joined(separator: ", "))
            say("학사편람".styled(.bold) + "  " + catalog.handbooks.map { String($0.year) }.joined(separator: ", "))
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "catalog.json을 파일 내용으로 바꾸기. 바뀐 행만 수정 시각이 바뀐다", discussion: """
            `folio catalog show --json`으로 받은 파일을 고쳐서 넣는다. 모르는 필드는 남는다.

            예시:
              folio catalog set --file catalog.json --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Option(help: ArgumentHelp("catalog.json 형식의 파일", valueName: "path"), completion: .file(extensions: ["json"])) var file: String

        func run() throws {
            try perform(spec: CatalogSet(catalog: try readJSON(Catalog.self, file)), g, ctx: try CLI.context(g))
        }
    }
}

struct SettingsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "settings", abstract: "settings.json: 하루 경계, 복습 간격, 알림, 백업", subcommands: [Show.self, Set.self])

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "설정 보기. --json이면 settings.json 전체", discussion: """
            예시:
              folio settings show
              folio settings show --json > settings.json
            """)
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let s = try CLI.context(g).settings()
            if g.json { return try printJSON(s) }
            say("하루 경계".styled(.bold) + String(format: "  %02d:%02d", s.dayBoundaryMinutes / 60, s.dayBoundaryMinutes % 60))
            say("복습 간격".styled(.bold) + "  " + s.review.intervals.map { "\($0)일" }.joined(separator: ", "))
            say("새 노트 수식".styled(.bold) + "  \(s.newNoteMath.rawValue)")
            say("자동 백업".styled(.bold) + "  \(s.backup.enabled ? s.backup.folder : "끔")")
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "설정 하나를 바꾸거나 settings.json 전체를 파일 내용으로 바꾸기", discussion: """
            필드는 settings.json의 이름을 점으로 이어 쓴다(`folio settings show --json`). 값은 JSON으로 읽고, JSON이 아니면 글자로 읽는다.
            있는 필드만 바꿀 수 있다. 모양이 맞지 않는 값은 쓰지 않는다(종료 코드 2).

            예시:
              folio settings set dayBoundaryMinutes 300
              folio settings set review.intervals "[1, 3, 7, 14, 30]" --dry-run
              folio settings set --file settings.json --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("필드. 예: review.intervals", valueName: "field")) var field: String?
        @Argument(help: ArgumentHelp("새 값", valueName: "value")) var value: String?
        @Option(help: ArgumentHelp("settings.json 형식의 파일", valueName: "path"), completion: .file(extensions: ["json"])) var file: String?

        func run() throws {
            if let file {
                guard field == nil else { throw CLIError(exit: .usage, message: "필드와 --file 중 하나만 주세요") }
                try perform(spec: SettingsSet(settings: try readJSON(Settings.self, file)), g, ctx: try CLI.context(g))
                return
            }
            guard let field, let value else { throw CLIError(exit: .usage, message: "필드와 값을 주세요: folio settings set <필드> <값>") }
            let ctx = try CLI.context(g)
            var root = try JSONDecoder.folio.decode(JSONValue.self, from: JSONEncoder.folio.encode(try ctx.settings()))
            let parsed = (try? JSONDecoder().decode(JSONValue.self, from: Data(value.utf8))) ?? .string(value)
            try root.set(field.split(separator: ".").map(String.init), to: parsed, path: field)
            let settings: Settings
            do {
                settings = try JSONDecoder.folio.decode(Settings.self, from: JSONEncoder.folio.encode(root))
            } catch let e as DecodingError {
                throw CLIError(exit: .usage, message: "\(field)에 맞지 않는 값입니다: \(RunCommand.describe(e))")
            }
            try perform(spec: SettingsSet(settings: settings), g, ctx: ctx)
        }
    }
}

extension JSONValue {
    /// Replaces the value at an existing key path; a key that isn't there is a typo, not a new setting.
    mutating func set(_ keys: [String], to value: JSONValue, path: String) throws {
        guard let key = keys.first else { self = value; return }
        guard case .object(var o) = self, var child = o[key] else {
            let known = if case .object(let o) = self { o.keys.sorted() } else { [String]() }
            throw CLIError(exit: .usage, message: "없는 설정입니다: \(path)", candidates: known)
        }
        try child.set(Array(keys.dropFirst()), to: value, path: path)
        o[key] = child
        self = .object(o)
    }
}
