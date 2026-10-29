import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Verdict: ExpressibleByArgument {}
extension QuizAttemptEvent.Grader: ExpressibleByArgument {}

extension Resolver {
    func card(_ ref: String, unit: FolioDomain.Unit, in c: CourseRef) throws -> QuizCard {
        guard let store = c.store else { throw CLIError(exit: .rule, message: "\(c.course.title)은(는) 과목 폴더가 없습니다") }
        return try pick(ref, try store.loadQuiz(unit: unit.id).model.cards, what: "카드", names: { [$0.prompt] }, ref: { $0.id.uuidString })
    }
}

struct QuizCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "quiz", abstract: "퀴즈 카드: 목록, 추가와 고치기, 지우기, 풀이 기록",
        subcommands: [List.self, Add.self, Remove.self, Record.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "단원별 퀴즈 카드", discussion: """
            예시:
              folio quiz list EC4207
              folio quiz list EC4207 --unit 매칭
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Option(help: ArgumentHelp("이 단원만", valueName: "unit"), completion: Complete.units) var unit: String?
        @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            guard let store = c.store else { throw CLIError(exit: .rule, message: "\(c.course.title)은(는) 과목 폴더가 없습니다") }
            let units = try unit.map { [try r.unit(c.local($0), in: c)] } ?? (try c.requireFile().units)
            let decks = try units.map { ($0, try store.loadQuiz(unit: $0.id).model.cards) }.filter { !$0.1.isEmpty }
            if g.json { return try printJSON(decks.flatMap(\.1)) }
            if lines {
                for (u, cards) in decks { for card in cards { line([card.id.uuidString, u.title, card.type.rawValue, card.prompt]) } }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: ["단원", "종류", "분류", "문제"], shrink: [3])
            for (u, cards) in decks { for card in cards { t.rows.append([u.title, card.type.rawValue, card.category.rawValue, card.prompt]) } }
            t.print()
            footer(decks.map(\.1.count).reduce(0, +))
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "JSON 파일의 카드를 넣거나 같은 ID의 카드를 바꾸기", discussion: """
            파일은 course.json과 같은 필드 이름을 쓰는 QuizCard 배열이다. 단원을 옮긴 카드는 --moved-from에 예전 단원을 준다.

            예시:
              folio quiz add EC4207 --file cards.json
              folio quiz add EC4207 --file - --moved-from 매칭 < card.json
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Option(help: ArgumentHelp("카드 JSON 파일. -이면 표준 입력", valueName: "file"), completion: .file()) var file: String
        @Option(help: ArgumentHelp("카드가 떠난 단원", valueName: "unit"), completion: Complete.units) var movedFrom: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let c = try r.course(course)
            let cards: [QuizCard]
            do {
                cards = try JSONDecoder.folio.decode([QuizCard].self, from: Data(try readText(file).utf8))
            } catch let e as DecodingError {
                throw CLIError(exit: .usage, message: "카드 형식이 맞지 않습니다: \(RunCommand.describe(e))")
            }
            try perform(spec: QuizCardSave(course: c.id, cards: cards, movedFrom: try movedFrom.map { try r.unit(c.local($0), in: c).id }), g, ctx: ctx)
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm", abstract: "카드 지우기. 풀이 기록은 남는다", discussion: """
            예시:
              folio quiz rm EC4207/매칭 3F2A9C1E-0000-4000-8000-000000000001
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<단원>", valueName: "unit"), completion: Complete.units) var unit: String
        @Argument(help: ArgumentHelp("카드 ID 또는 문제 글", valueName: "card")) var card: String

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(unit)
            let u = try r.unit(name, in: c)
            try perform(spec: QuizCardRemove(course: c.id, unit: u.id, card: try r.card(card, unit: u, in: c).id), g, ctx: ctx)
        }
    }

    struct Record: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "카드 풀이 결과를 기록", discussion: """
            예시:
              folio quiz record EC4207/매칭 "최대 매칭의 정의" correct --grader self
              folio quiz record EC4207/매칭 3F2A9C1E-0000-4000-8000-000000000001 wrong --grader ai --answer "모름"
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<단원>", valueName: "unit"), completion: Complete.units) var unit: String
        @Argument(help: ArgumentHelp("카드 ID 또는 문제 글", valueName: "card")) var card: String
        @Argument(help: "판정. correct, partial, wrong") var verdict: Verdict
        @Option(help: "채점한 쪽. ai 또는 self") var grader: QuizAttemptEvent.Grader = .self
        @Option(help: ArgumentHelp("쓴 답", valueName: "answer")) var answer: String?

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
        commandName: "problem-set", abstract: "문제 묶음: 연습 문제와 과제의 문제 번호, 단원 연결, 풀이 기록",
        subcommands: [List.self, Add.self, Record.self] + GeneratedCommands.problemSet)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목의 문제 묶음", discussion: """
            예시:
              folio problem-set list EC4207
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let sets = try c.requireFile().problemSets
            if g.json { return try printJSON(sets) }
            if lines {
                for s in sets { line(["\(c.code)/\(s.title)", "\(s.problems.count)문제"]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: ["묶음", "문제"], shrink: [1])
            for s in sets { t.rows.append([s.title, s.problems.map(\.number).joined(separator: " ")]) }
            t.print()
            footer(sets.count)
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "문제 번호로 문제 묶음 만들기", discussion: """
            있는 묶음을 고치려면 folio run problem-set add --input으로 묶음 전체를 준다.

            예시:
              folio problem-set add EC4207 "Exercise 1" --problems 1 2 3a 3b
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String
        @Argument(help: ArgumentHelp("제목", valueName: "title")) var title: String
        @Option(parsing: .upToNextOption, help: ArgumentHelp("문제 번호들", valueName: "number")) var problems: [String] = []
        @Option(help: .hidden) var id: UUID?

        func run() throws {
            let ctx = try CLI.context(g)
            let c = try Resolver(ctx).course(course)
            let set = ProblemSet(id: id ?? UUID(), device: ctx.device, at: ctx.now, title: title, problems: problems.map { .init(number: $0) })
            try perform(spec: ProblemSetSave(course: c.id, set: set), g, ctx: ctx)
        }
    }

    struct Record: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "문제 풀이 결과를 기록", discussion: """
            예시:
              folio problem-set record "EC4207/Exercise 1" 3a wrong
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<묶음>", valueName: "batch"), completion: Complete.problemSets) var set: String
        @Argument(help: ArgumentHelp("문제 번호", valueName: "number")) var number: String
        @Argument(help: "판정. correct, partial, wrong") var verdict: Verdict

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(set)
            let s = try r.problemSet(name, in: c)
            guard s.problems.contains(where: { $0.number == number }) else { throw CLIError(exit: .notFound, message: "문제 \(number)을(를) 찾지 못했습니다") }
            try perform(spec: ProblemRecord(course: c.id, attempt: ProblemAttemptEvent(problemSetId: s.id, number: number, verdict: verdict)), g, ctx: ctx)
        }
    }
}

struct ReviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review", abstract: "단원 복습: 결과 기록, 복습 건너뛰기",
        subcommands: GeneratedCommands.review + [Skip.self])

    struct Skip: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "단원을 복습하지 않아도 되는 것으로 표시. 여러 개면 확인을 받는다", discussion: """
            예시:
              folio review skip EC4207/매칭
              folio review skip EC4207/매칭 EC4321/기구학
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<단원>. 여러 과목을 섞어도 된다", valueName: "unit"), completion: Complete.units) var units: [String]

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
