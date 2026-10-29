import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct ExamCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exam", abstract: "시험: 목록, 추가, 범위 단원, 공부 계획, 종합 정리",
        subcommands: [List.self, Show.self] + GeneratedCommands.exam + [Scope.self, Plan.self, PlanCheck.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목의 시험 목록", discussion: """
            예시:
              folio exam list EC4207
              folio exam list EC4207 --lines
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목. 강의 코드, 폴더 이름, 과목 이름, UUID", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let exams = try c.requireFile().exams.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
            if g.json { return try printJSON(exams) }
            if lines {
                for e in exams { line(["\(c.code)/\(e.title)", e.title, e.start.map { $0.formatted(date: .numeric, time: .shortened) } ?? "", e.kind.rawValue]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: ["시험", "일시", "종류", "장소", "범위"], shrink: [3])
            for e in exams {
                let cells = [e.title, e.start.map { when($0, now: r.ctx.now, time: true) } ?? "-", e.kind.rawValue.toned, e.location,
                             e.scopeUnitIds.isEmpty ? "" : "단원 \(e.scopeUnitIds.count)개"]
                t.rows.append((e.end ?? e.start).map { $0 < r.ctx.now } ?? false ? cells.map { $0.styled(.dim) } : cells)
            }
            t.print()
            footer(exams.count)
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "시험 하나의 자세한 내용: 범위 단원, 공부 계획", discussion: """
            예시:
              folio exam show EC4207/중간고사
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<시험>. 예: EC4207/Quiz1", valueName: "exam"), completion: Complete.exams) var exam: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(exam)
            let e = try r.exam(name, in: c)
            if g.json { return try printJSON(e) }
            let f = try c.requireFile()
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(e.title.styled(.bold))
            say("  종류  \(e.kind.rawValue)")
            if let start = e.start { say("  일시  \(when(start, now: r.ctx.now, time: true))" + (e.end.map { " – \($0.formatted(date: .omitted, time: .shortened))" } ?? "")) }
            if !e.location.isEmpty { say("  장소  \(e.location)") }
            if let comp = e.componentId.flatMap({ id in f.components.first { $0.id == id } }) { say("  성적 항목  \(comp.name)") }
            let units = UnitTree.outline(f.units).map(\.unit).filter { e.scopeUnitIds.contains($0.id) }
            if !units.isEmpty {
                say("  범위 단원")
                for u in units { say("    \(u.title)") }
            }
            if !e.plan.isEmpty {
                say("  공부 계획")
                for item in e.plan.sorted(by: { $0.day < $1.day }) { say("    \(item.day)  \(item.title)") }
            }
        }
    }

    struct Scope: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "시험 범위에 단원 넣기, --off면 빼기", discussion: """
            단원을 넣으면 그 하위 단원도 함께 들어간다. --taught는 시험 전에 지난 회차에 연결된 단원과 그 상위 단원을 모두 넣는다.

            예시:
              folio exam scope EC4207/Quiz1 --unit 트리 --unit 매칭
              folio exam scope EC4207/중간고사 --taught --dry-run
              folio exam scope EC4207/Quiz1 --unit 매칭 --off
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<시험>", valueName: "exam"), completion: Complete.exams) var exam: String = ""
        @Option(name: .customLong("unit"), help: ArgumentHelp("단원. 여러 번 줄 수 있다", valueName: "unit"), completion: Complete.units) var units: [String] = []
        @Flag(help: "범위에서 빼기") var off = false
        @Flag(help: "시험 전에 배운 단원을 모두 넣기") var taught = false

        func run() throws {
            guard !(taught && !units.isEmpty), !(taught && off) else {
                throw CLIError(exit: .usage, message: "--unit이나 --taught 중 하나만 주세요")
            }
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(exam)
            let e = try r.exam(name, in: c)
            if taught {
                try perform(spec: ExamScopeTaught(course: c.id, exam: e.id), g, ctx: ctx)
                return
            }
            let ids = try r.many(units, from: try c.requireFile().units.map(\.title), what: "단원").map { try r.unit($0, in: c).id }
            try performAll(ids.map { ExamScope(course: c.id, exam: e.id, unit: $0, included: !off) }, g, ctx: ctx,
                           done: off ? "단원 \(ids.count)개를 범위에서 뺐습니다" : "단원 \(ids.count)개를 범위에 넣었습니다")
        }
    }

    struct Plan: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "시험 공부 계획 항목 추가와 지우기", subcommands: GeneratedCommands.examPlan + [Remove.self])

        struct Remove: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "rm", abstract: "공부 계획 항목 지우기. 확인을 받는다", discussion: """
                예시:
                  folio exam plan rm EC4207/중간고사 "트리 단원 복습" --dry-run
                """)
            @OptionGroup var g: GlobalOptions
            @Argument(help: ArgumentHelp("<과목>/<시험>", valueName: "exam"), completion: Complete.exams) var exam: String
            @Argument(help: ArgumentHelp("항목 제목이나 UUID", valueName: "item")) var item: String = ""

            func run() throws {
                let ctx = try CLI.context(g)
                let r = Resolver(ctx)
                let (c, name) = try r.split(exam)
                let e = try r.exam(name, in: c)
                let i = try r.planItem(item, in: e, course: c)
                try perform(spec: ExamPlanRemove(course: c.id, exam: e.id, item: i.id), g, ctx: ctx)
            }
        }
    }

    struct PlanCheck: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "plan-check", abstract: "공부 계획 항목 끝내기, --undo면 되돌리기", discussion: """
            예시:
              folio exam plan-check EC4207/중간고사 "트리 단원 복습"
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<시험>", valueName: "exam"), completion: Complete.exams) var exam: String
        @Argument(help: ArgumentHelp("항목 제목이나 UUID", valueName: "item")) var item: String = ""
        @Flag(help: "끝내지 않은 것으로 되돌리기") var undo = false

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(exam)
            let i = try r.planItem(item, in: try r.exam(name, in: c), course: c)
            try perform(ExamPlanCheck(course: c.id, item: i.id, done: !undo), g, ctx: ctx, done: undo ? "'\(i.title)'을(를) 끝내지 않은 것으로 되돌렸습니다" : "'\(i.title)'을(를) 끝냈습니다")
        }
    }
}

extension Resolver {
    func planItem(_ name: String, in exam: Exam, course c: CourseRef) throws -> ExamPlanItem {
        try pick(name, exam.plan, what: "공부 계획 항목", names: { [$0.title] }, ref: { "\(c.code)/\(exam.title) \($0.title)" })
    }
}
