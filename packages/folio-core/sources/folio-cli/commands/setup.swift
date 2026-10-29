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

func readJSON<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
    let url = URL(filePath: (path as NSString).expandingTildeInPath)
    guard let data = try? Data(contentsOf: url) else { throw CLIError(exit: .usage, message: String(localized: .readJsonUnreadable(path))) }
    do {
        return try JSONDecoder.folio.decode(T.self, from: data)
    } catch let e as DecodingError {
        throw CLIError(exit: .usage, message: String(localized: .readJsonBadFormat(RunCommand.describe(e))))
    }
}

struct SemesterCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "semester", abstract: String(localized: .semesterAbstract),
        subcommands: [List.self, Show.self] + GeneratedCommands.semester)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .semesterListAbstract), discussion: String(localized: .semesterListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

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
            var t = Table(header: [String(localized: .semesterListHeaderSemester), String(localized: .semesterListHeaderName), String(localized: .semesterListHeaderSpan)])
            for s in semesters {
                let cells = [s.folder?.name ?? String(localized: .semesterRecognized), "\(s.year) \(s.term.rawValue)", span(s)]
                t.rows.append(s.id == current ? cells.map { $0.styled(.bold) } : cells)
            }
            t.print()
            footer(semesters.count)
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .semesterShowAbstract), discussion: String(localized: .semesterShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .semesterShowHelpSemester), valueName: "semester"), completion: .custom(Complete.semesters)) var semester: String?

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let s = try r.semester(semester)
            if g.json { return try printJSON(s) }
            say((s.folder?.name ?? String(localized: .semesterRecognized)).styled(.bold) + "  \(s.year) \(s.term.rawValue)".styled(.dim))
            say(String(localized: .semesterShowStart(s.start?.description ?? "-")))
            say(String(localized: .semesterShowEnd(s.end?.description ?? "-")))
            if let w = s.midtermWeek { say(String(localized: .semesterShowMidterm(w))) }
            if let w = s.finalWeek { say(String(localized: .semesterShowFinal(w))) }
            let courses = r.courses.filter { $0.course.semesterId == s.id }
            if !courses.isEmpty {
                say(String(localized: .semesterShowCourses))
                for c in courses { say("    " + "●".course(c.color) + " \(c.tag) \(c.course.title)") }
            }
        }
    }
}

struct CourseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "course", abstract: String(localized: .courseAbstract),
        subcommands: [List.self, Show.self, Add.self, Rename.self, Set.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .courseListAbstract), discussion: String(localized: .courseListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Option(help: ArgumentHelp(String(localized: .courseListHelpSemester), valueName: "semester"), completion: .custom(Complete.semesters)) var semester: String?
        @Flag(help: ArgumentHelp(String(localized: .courseListHelpAll))) var all = false
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let semesterId = all ? nil : try r.semester(semester).id
            let courses = r.courses.filter { semesterId == nil || $0.course.semesterId == semesterId }
            if g.json { return try printJSON(courses.map(\.course)) }
            if lines {
                for c in courses { line([c.code, c.course.title, String(localized: .courseListCredits(c.course.credits.formatted()))]) }
                return
            }
            let catalog = try? r.ctx.catalog()
            var t = Table(header: ["", String(localized: .courseListHeaderCode), String(localized: .courseListHeaderCourse), String(localized: .courseListHeaderCredits), String(localized: .courseListHeaderMode), String(localized: .courseListHeaderGrade)], shrink: [2])
            for c in courses {
                t.rows.append(["●".course(c.color), c.tag, c.course.title, c.course.credits.formatted(), c.course.gradingMode.rawValue.toned,
                               catalog?.grade(c.course.finalGrade).map { GradesLock.masked($0.symbol) } ?? ""])
            }
            t.print()
            footer(courses.count, hidden: all ? nil : String(localized: .courseListHiddenAll))
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .courseShowAbstract), discussion: String(localized: .courseShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            if g.json { return try printJSON(c.course) }
            let catalog = try? r.ctx.catalog()
            courseHeader(c, catalog: catalog)
            let x = c.course
            say(String(localized: .courseShowCredits(x.credits.formatted())))
            say(String(localized: .courseShowMode(x.gradingMode.rawValue)))
            if let grade = catalog?.grade(x.finalGrade) { say(String(localized: .courseShowGrade(GradesLock.masked(grade.symbol)))) }
            let categories = x.categoryIds.compactMap { catalog?.category($0)?.name }
            if !categories.isEmpty { say(String(localized: .courseShowCategories(categories.joined(separator: ", ")))) }
            if x.reviews == false { say(String(localized: .courseShowReviewsOff)) }
            if !x.schedule.isEmpty {
                say(String(localized: .courseShowSchedule))
                for t in x.schedule {
                    say("    \(ClassTime.weekdayNames[t.weekday - 1]) \(String(format: "%02d:%02d–%02d:%02d", t.startMinute / 60, t.startMinute % 60, t.endMinute / 60, t.endMinute % 60)) \(t.room)")
                }
            }
            if x.sharingApproved == true { say(String(localized: .courseShowSharingApproved)) }
            if !x.memo.isEmpty { say(String(localized: .courseShowMemo(x.memo))) }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .courseAddAbstract), discussion: String(localized: .courseAddDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .courseAddHelpCode), valueName: "code")) var code: String
        @Argument(help: ArgumentHelp(String(localized: .courseAddHelpNumber), valueName: "number")) var number: String
        @Argument(help: ArgumentHelp(String(localized: .commonHelpTitle), valueName: "name")) var title: String
        @Option(help: ArgumentHelp(String(localized: .commonHelpCredits))) var credits: Double = 3
        @Option(help: ArgumentHelp(String(localized: .commonHelpMode))) var mode: GradingMode = .relative
        @Option(help: ArgumentHelp(String(localized: .courseAddHelpSemester), valueName: "semester"), completion: .custom(Complete.semesters)) var semester: String?
        @Option(help: .hidden) var id: UUID?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            try perform(spec: CourseAdd(id: id ?? UUID(), semester: try r.semester(semester).id, title: title, code: try r.code(code).id, number: number,
                                        credits: credits, mode: mode), g, ctx: ctx)
        }
    }

    struct Rename: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .courseRenameAbstract), discussion: String(localized: .courseRenameDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Option(help: ArgumentHelp(String(localized: .commonHelpTitle))) var title: String?
        @Option(help: ArgumentHelp(String(localized: .courseRenameHelpCode), valueName: "code")) var code: [String] = []
        @Option(help: ArgumentHelp(String(localized: .courseRenameHelpNumber))) var number: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let c = try r.course(course)
            let codes = code.isEmpty ? c.course.codes : try code.map { try r.code($0).id }
            try perform(spec: CourseRename(course: c.id, title: title ?? c.course.title, codes: codes, number: number ?? c.course.number), g, ctx: ctx)
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .courseSetAbstract), discussion: String(localized: .courseSetDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Option(help: ArgumentHelp(String(localized: .commonHelpMemo))) var memo: String?
        @Option(help: ArgumentHelp(String(localized: .commonHelpCredits))) var credits: Double?
        @Option(help: ArgumentHelp(String(localized: .commonHelpMode))) var mode: GradingMode?
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpColor), valueName: "color")) var color: String?
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpIcon), valueName: "symbol")) var icon: String?
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpReviews))) var reviews: Toggle?
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpSharingApproved))) var sharingApproved: Toggle?
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpGrade), valueName: "grade")) var grade: String?
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpInstructor), valueName: "name")) var instructor: [String] = []
        @Option(help: ArgumentHelp(String(localized: .courseSetHelpCategory), valueName: "category")) var category: [String] = []

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
            guard !fields.isEmpty else { throw CLIError(exit: .usage, message: String(localized: .courseSetNothingToChange)) }
            try perform(spec: CourseSet(course: c.id, fields), g, ctx: ctx)
        }
    }
}

struct CatalogCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "catalog", abstract: String(localized: .catalogAbstract), subcommands: [Show.self, Set.self])

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .catalogShowAbstract), discussion: String(localized: .catalogShowDiscussion))
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let catalog = try CLI.context(g).catalog()
            if g.json { return try printJSON(catalog) }
            say(String(localized: .catalogShowCodes).styled(.bold) + "  " + catalog.codes.map(\.prefix).joined(separator: " "))
            say(String(localized: .catalogShowLetterGrades).styled(.bold) + "  " + catalog.letterGrades.map(\.symbol).joined(separator: " "))
            say(String(localized: .catalogShowCategories).styled(.bold) + "  " + String(localized: .catalogShowCategoryCount(catalog.categories.count)))
            say(String(localized: .catalogShowPeople).styled(.bold) + "  " + catalog.people.map(\.name).joined(separator: ", "))
            say(String(localized: .catalogShowHandbooks).styled(.bold) + "  " + catalog.handbooks.map { String($0.year) }.joined(separator: ", "))
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .catalogSetAbstract), discussion: String(localized: .catalogSetDiscussion))
        @OptionGroup var g: GlobalOptions
        @Option(help: ArgumentHelp(String(localized: .catalogSetHelpFile), valueName: "path"), completion: .file(extensions: ["json"])) var file: String

        func run() throws {
            try perform(spec: CatalogSet(catalog: try readJSON(Catalog.self, file)), g, ctx: try CLI.context(g))
        }
    }
}

struct SettingsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "settings", abstract: String(localized: .settingsAbstract), subcommands: [Show.self, Set.self])

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .settingsShowAbstract), discussion: String(localized: .settingsShowDiscussion))
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let s = try CLI.context(g).settings()
            if g.json { return try printJSON(s) }
            say(String(localized: .settingsShowDayBoundary).styled(.bold) + String(format: "  %02d:%02d", s.dayBoundaryMinutes / 60, s.dayBoundaryMinutes % 60))
            say(String(localized: .settingsShowIntervals).styled(.bold) + "  " + s.review.intervals.map { String(localized: .settingsShowDays($0)) }.joined(separator: ", "))
            say(String(localized: .settingsShowNewNoteMath).styled(.bold) + "  \(s.newNoteMath.rawValue)")
            say(String(localized: .settingsShowBackup).styled(.bold) + "  \(s.backup.enabled ? s.backup.folder : String(localized: .settingsShowOff))")
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .settingsSetAbstract), discussion: String(localized: .settingsSetDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .settingsSetHelpField), valueName: "field")) var field: String?
        @Argument(help: ArgumentHelp(String(localized: .settingsSetHelpValue), valueName: "value")) var value: String?
        @Option(help: ArgumentHelp(String(localized: .settingsSetHelpFile), valueName: "path"), completion: .file(extensions: ["json"])) var file: String?

        func run() throws {
            if let file {
                guard field == nil else { throw CLIError(exit: .usage, message: String(localized: .settingsSetFieldOrFile)) }
                try perform(spec: SettingsSet(settings: try readJSON(Settings.self, file)), g, ctx: try CLI.context(g))
                return
            }
            guard let field, let value else { throw CLIError(exit: .usage, message: String(localized: .settingsSetNeedsFieldAndValue)) }
            let ctx = try CLI.context(g)
            var root = try JSONDecoder.folio.decode(JSONValue.self, from: JSONEncoder.folio.encode(try ctx.settings()))
            let parsed = (try? JSONDecoder().decode(JSONValue.self, from: Data(value.utf8))) ?? .string(value)
            try root.set(field.split(separator: ".").map(String.init), to: parsed, path: field)
            let settings: Settings
            do {
                settings = try JSONDecoder.folio.decode(Settings.self, from: JSONEncoder.folio.encode(root))
            } catch let e as DecodingError {
                throw CLIError(exit: .usage, message: String(localized: .settingsSetBadValue(field, RunCommand.describe(e))))
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
            throw CLIError(exit: .usage, message: String(localized: .settingsSetUnknownField(path)), candidates: known)
        }
        try child.set(Array(keys.dropFirst()), to: value, path: path)
        o[key] = child
        self = .object(o)
    }
}
