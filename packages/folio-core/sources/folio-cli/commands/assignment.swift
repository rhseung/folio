import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct AssignmentCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assignment", abstract: "과제: 목록, 추가, 상태, 바꾸기",
        subcommands: [List.self, Show.self, Set.self] + GeneratedCommands.assignment)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목의 과제 목록. 기본은 아직 낼 것만", discussion: """
            예시:
              folio assignment list EC4207
              folio assignment list EC4207 --all --lines
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목. 강의 코드, 폴더 이름, 과목 이름, UUID", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: "낸 것과 채점된 것까지") var all = false
        @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = try c.requireFile()
            let items = f.assignments.filter { all || $0.status == .todo || $0.status == .doing }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            if g.json { return try printJSON(items) }
            if lines {
                for a in items { line(["\(c.code)/\(a.title)", a.title, a.due.map { $0.formatted(date: .numeric, time: .shortened) } ?? "", a.status.rawValue]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: ["과제", "마감", "상태", "성적 항목"], shrink: [3])
            for a in items {
                let late = a.due.map { $0 < r.ctx.now } ?? false
                let due = a.due.map { when($0, now: r.ctx.now, time: true) } ?? "-"
                let open = a.status == .todo || a.status == .doing
                t.rows.append([a.title, late && open ? due.plain.styled(.red) : due, a.status.rawValue.toned,
                               a.componentId.flatMap { id in f.components.first { $0.id == id }?.name } ?? a.componentGroup ?? ""])
            }
            t.print()
            footer(items.count, hidden: all ? nil : "--all로 낸 것까지")
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과제 하나의 자세한 내용과 점수", discussion: """
            예시:
              folio assignment show EC4207/HW3
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<과제>. 예: EC4207/HW3", valueName: "assignment"), completion: Complete.assignments) var assignment: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(assignment)
            let a = try r.assignment(name, in: c)
            if g.json { return try printJSON(a) }
            let f = try c.requireFile()
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(a.title.styled(.bold))
            if let due = a.due { say("  마감  \(when(due, now: r.ctx.now, time: true))") }
            say("  상태  \(a.status.rawValue.toned)")
            if a.repeats == .weekly { say("  반복  매주") }
            if !a.memo.isEmpty { say("  메모  \(a.memo)") }
            let scores = f.scores.filter { $0.assignmentId == a.id }
            if !scores.isEmpty {
                say("  점수")
                for s in scores {
                    let comp = f.components.first { $0.id == s.componentId }?.name ?? ""
                    say("    \(comp)  \(GradesLock.masked("\(s.score.formatted())/\(s.max.formatted())"))")
                }
            }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과제의 제목, 마감, 상태, 성적 항목, 메모 바꾸기. 준 것만 바뀐다", discussion: """
            성적 항목이나 묶음을 바꾸면 이전 항목에 매긴 점수는 지워진다. 점수를 주면 상태는 graded가 된다.
            값을 지우려면 none을 준다.

            예시:
              folio assignment set EC4207/HW3 --due "2026-11-06 23:59"
              folio assignment set EC4207/HW3 --component 과제 --memo "3번 질문함"
              folio assignment set EC4207/HW3 --component 과제 --score 9/10
              folio assignment set EC4207/HW3 --due none --repeats weekly --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<과제>", valueName: "assignment"), completion: Complete.assignments) var assignment: String = ""
        @Option(help: ArgumentHelp("새 제목", valueName: "title")) var title: String?
        @Option(help: ArgumentHelp("마감 일시. none이면 지운다", valueName: "when")) var due: Clearable<DateArg>?
        @Option(help: "상태") var status: AssignmentStatus?
        @Option(help: "반복. none이면 반복하지 않는다") var repeats: Clearable<AssignmentRepeat>?
        @Option(help: ArgumentHelp("반영되는 성적 항목. none이면 풀기", valueName: "item")) var component: Clearable<String>?
        @Option(help: ArgumentHelp("한꺼번에 점수를 매기는 성적 항목 묶음. none이면 풀기", valueName: "group")) var group: Clearable<String>?
        @Option(help: ArgumentHelp("점수 9/10. 묶음이면 <항목>:9/10. 여러 번 줄 수 있고, none이면 점수를 모두 지운다", valueName: "score")) var score: [String] = []
        @Option(help: ArgumentHelp("메모", valueName: "memo")) var memo: String?

        func run() throws {
            guard component == nil || group == nil else { throw CLIError(exit: .usage, message: "--component와 --group 중 하나만 주세요") }
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(assignment)
            let a = try r.assignment(name, in: c)
            let f = try c.requireFile()
            var componentId = a.componentId, componentGroup = a.componentGroup
            if let component { componentId = try component.value.map { try r.component($0, in: c).id }; componentGroup = nil }
            if let group {
                guard group.value.map({ g in f.components.contains { $0.group == g } }) ?? true else {
                    throw CLIError(exit: .notFound, message: "성적 항목 묶음을 찾지 못했습니다: \(group.value ?? "")",
                                   candidates: Array(Swift.Set(f.components.compactMap(\.group))).sorted())
                }
                (componentGroup, componentId) = (group.value, group.value == nil ? componentId : nil)
            }
            // The sheet always sends every covered component and its scores; one left out would lose its score.
            let covered = componentGroup.map { g in f.components.filter { $0.group == g }.map(\.id) } ?? componentId.map { [$0] } ?? []
            var scores = f.scores.filter { $0.assignmentId == a.id }.map { AssignmentSave.Score(component: $0.componentId, score: $0.score, max: $0.max) }
            if score == ["none"] { scores = [] }
            for s in score where s != "none" {
                let (target, value) = s.firstIndex(of: ":").map { (String(s[..<$0]), String(s[s.index(after: $0)...])) } ?? (nil, s)
                let parts = value.split(separator: "/").compactMap { Double($0) }
                guard parts.count == 2 else { throw CLIError(exit: .usage, message: "점수는 9/10 꼴로 주세요: \(s)") }
                let id: UUID
                if let target { id = try r.component(target, in: c).id } else if covered.count == 1 { id = covered[0] } else {
                    throw CLIError(exit: .usage, message: covered.isEmpty ? "점수를 매길 성적 항목이 없습니다. --component를 함께 주세요" : "묶음이면 <항목>:9/10 꼴로 주세요")
                }
                guard covered.contains(id) else { throw CLIError(exit: .rule, message: "과제가 반영되지 않는 성적 항목입니다: \(target ?? "")") }
                scores.removeAll { $0.component == id }
                scores.append(AssignmentSave.Score(component: id, score: parts[0], max: parts[1]))
            }
            try perform(spec: AssignmentSave(course: c.id, assignment: a.id, title: title ?? a.title, due: due.map(\.value?.date) ?? a.due, status: status ?? a.status,
                                       repeats: repeats.map(\.value) ?? a.repeats, componentId: componentId, componentGroup: componentGroup, memo: memo ?? a.memo,
                                       components: covered, scores: scores),
                        g, ctx: ctx)
        }
    }
}
