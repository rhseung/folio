import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Verdict: ExpressibleByArgument {}
extension QuizAttemptEvent.Grader: ExpressibleByArgument {}

extension Resolver {
    func card(_ ref: String, unit: FolioDomain.Unit, in c: CourseRef) throws -> QuizCard {
        guard let store = c.store else { throw CLIError(exit: .rule, message: String(localized: .quizNoCourseFolder(c.course.title))) }
        return try pick(ref, try store.loadQuiz(unit: unit.id).model.cards, what: "카드", names: { [$0.prompt] }, ref: { $0.id.uuidString })
    }
}

struct QuizCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quiz", abstract: String(localized: .quizAbstract),
        subcommands: [List.self, Add.self, Remove.self, Record.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .quizListAbstract), discussion: String(localized: .quizListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Option(help: ArgumentHelp(String(localized: .quizListHelpUnit), valueName: "unit"), completion: Complete.units) var unit: String?
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            guard let store = c.store else { throw CLIError(exit: .rule, message: String(localized: .quizNoCourseFolder(c.course.title))) }
            let units = try unit.map { [try r.unit(c.local($0), in: c)] } ?? (try c.requireFile().units)
            let decks = try units.map { ($0, try store.loadQuiz(unit: $0.id).model.cards) }.filter { !$0.1.isEmpty }
            if g.json { return try printJSON(decks.flatMap(\.1)) }
            if lines {
                for (u, cards) in decks { for card in cards { line([card.id.uuidString, u.title, card.type.rawValue, card.prompt]) } }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: [String(localized: .quizListHeaderUnit), String(localized: .quizListHeaderKind), String(localized: .quizListHeaderCategory), String(localized: .quizListHeaderPrompt)], shrink: [3])
            for (u, cards) in decks { for card in cards { t.rows.append([u.title, card.type.rawValue, card.category.rawValue, card.prompt]) } }
            t.print()
            footer(decks.map(\.1.count).reduce(0, +))
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .quizAddAbstract), discussion: String(localized: .quizAddDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Option(help: ArgumentHelp(String(localized: .quizAddHelpFile), valueName: "file"), completion: .file()) var file: String
        @Option(help: ArgumentHelp(String(localized: .quizAddHelpMovedFrom), valueName: "unit"), completion: Complete.units) var movedFrom: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let c = try r.course(course)
            let cards: [QuizCard]
            do {
                cards = try JSONDecoder.folio.decode([QuizCard].self, from: Data(try readText(file).utf8))
            } catch let e as DecodingError {
                throw CLIError(exit: .usage, message: String(localized: .quizAddBadCards(RunCommand.describe(e))))
            }
            try perform(spec: QuizCardSave(course: c.id, cards: cards, movedFrom: try movedFrom.map { try r.unit(c.local($0), in: c).id }), g, ctx: ctx)
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm", abstract: String(localized: .quizRmAbstract), discussion: String(localized: .quizRmDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpUnit), valueName: "unit"), completion: Complete.units) var unit: String
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCard), valueName: "card")) var card: String

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(unit)
            let u = try r.unit(name, in: c)
            try perform(spec: QuizCardRemove(course: c.id, unit: u.id, card: try r.card(card, unit: u, in: c).id), g, ctx: ctx)
        }
    }

    struct Record: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .quizRecordAbstract), discussion: String(localized: .quizRecordDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpUnit), valueName: "unit"), completion: Complete.units) var unit: String
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCard), valueName: "card")) var card: String
        @Argument(help: ArgumentHelp(String(localized: .commonHelpVerdict))) var verdict: Verdict
        @Option(help: ArgumentHelp(String(localized: .quizRecordHelpGrader))) var grader: QuizAttemptEvent.Grader = .self
        @Option(help: ArgumentHelp(String(localized: .quizRecordHelpAnswer), valueName: "answer")) var answer: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(unit)
            let u = try r.unit(name, in: c)
            let id = try r.card(card, unit: u, in: c).id
            try perform(spec: QuizRecord(course: c.id, attempt: QuizAttemptEvent(cardId: id, answer: answer, verdict: verdict, grader: grader)), g, ctx: ctx)
        }
    }
}

struct ProblemSetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "problem-set", abstract: String(localized: .problemSetAbstract),
        subcommands: [List.self, Add.self, Record.self] + GeneratedCommands.problemSet)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .problemSetListAbstract), discussion: String(localized: .problemSetListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let sets = try c.requireFile().problemSets
            if g.json { return try printJSON(sets) }
            if lines {
                for s in sets { line(["\(c.code)/\(s.title)", String(localized: .problemSetListProblems(s.problems.count))]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: [String(localized: .problemSetListHeaderSet), String(localized: .problemSetListHeaderProblems)], shrink: [1])
            for s in sets { t.rows.append([s.title, s.problems.map(\.number).joined(separator: " ")]) }
            t.print()
            footer(sets.count)
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .problemSetAddAbstract), discussion: String(localized: .problemSetAddDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String
        @Argument(help: ArgumentHelp(String(localized: .problemSetAddHelpTitle), valueName: "title")) var title: String
        @Option(parsing: .upToNextOption, help: ArgumentHelp(String(localized: .problemSetAddHelpProblems), valueName: "number")) var problems: [String] = []
        @Option(help: .hidden) var id: UUID?

        func run() throws {
            let ctx = try CLI.context(g)
            let c = try Resolver(ctx).course(course)
            let set = ProblemSet(id: id ?? UUID(), device: ctx.device, at: ctx.now, title: title, problems: problems.map { .init(number: $0) })
            try perform(spec: ProblemSetSave(course: c.id, set: set), g, ctx: ctx)
        }
    }

    struct Record: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .problemSetRecordAbstract), discussion: String(localized: .problemSetRecordDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .problemSetRecordHelpSet), valueName: "batch"), completion: Complete.problemSets) var set: String
        @Argument(help: ArgumentHelp(String(localized: .problemSetRecordHelpNumber), valueName: "number")) var number: String
        @Argument(help: ArgumentHelp(String(localized: .commonHelpVerdict))) var verdict: Verdict

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(set)
            let s = try r.problemSet(name, in: c)
            guard s.problems.contains(where: { $0.number == number }) else { throw CLIError(exit: .notFound, message: String(localized: .problemSetRecordNotFound(number))) }
            try perform(spec: ProblemRecord(course: c.id, attempt: ProblemAttemptEvent(problemSetId: s.id, number: number, verdict: verdict)), g, ctx: ctx)
        }
    }
}

struct ReviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review", abstract: String(localized: .reviewAbstract),
        subcommands: GeneratedCommands.review + [Skip.self])

    struct Skip: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .reviewSkipAbstract), discussion: String(localized: .reviewSkipDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .reviewSkipHelpUnits), valueName: "unit"), completion: Complete.units) var units: [String]

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let targets = try units.map { ref in
                let (c, name) = try r.split(ref)
                return ReviewSkip.Target(course: c.id, unit: try r.unit(name, in: c).id)
            }
            try perform(spec: ReviewSkip(units: targets), g, ctx: ctx)
        }
    }
}
