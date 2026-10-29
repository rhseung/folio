import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct SessionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session", abstract: "강의 회차: 목록, 추가, 휴강 표시, 러프·복습 노트",
        subcommands: [List.self, Show.self] + GeneratedCommands.session + [Remove.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목의 회차 목록", discussion: """
            예시:
              folio session list EC4207           그래프 이론의 회차
              folio session list EC4207 --lines   fzf에 넘길 줄 형식
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목. 강의 코드, 폴더 이름, 과목 이름, UUID", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: "휴강한 회차까지") var all = false
        @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = try c.requireFile()
            let sessions = f.sessions.sorted { $0.date < $1.date }.filter { all || !$0.isCancelled }
            if g.json { return try printJSON(sessions) }
            if lines {
                for s in sessions { line(["\(c.code)/\(f.name(of: s))", s.date.formatted(date: .numeric, time: .shortened), s.isCancelled ? "휴강" : "", s.topic]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: ["회차", "날짜", "휴강", "주제", "노트"], shrink: [3])
            for s in sessions {
                let notes = [s.roughNoteId.map { _ in "러프" }, s.reviewNoteId.map { _ in s.reviewNoteUnfinished == true ? "복습 노트 마저 쓰기" : "복습" }].compactMap { $0 }
                let cells = [f.name(of: s), when(s.date, now: r.ctx.now, time: true), s.isCancelled ? "휴강".toned : "", s.topic, notes.joined(separator: " · ")]
                t.rows.append(s.date < r.ctx.now ? cells.map { $0.styled(.dim) } : cells)
            }
            t.print()
            footer(sessions.count, hidden: all ? nil : "--all로 휴강까지")
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "회차 하나의 자세한 내용", discussion: """
            예시:
              folio session show EC4207/9주차-1
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<회차>. 예: EC4207/9주차-1", valueName: "session"), completion: Complete.sessions) var session: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(session)
            let s = try r.session(name, in: c)
            if g.json { return try printJSON(s) }
            let f = try c.requireFile()
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(f.name(of: s).styled(.bold))
            say("  날짜  \(when(s.date, now: r.ctx.now, time: true))")
            if s.isCancelled { say("  휴강") }
            if !s.topic.isEmpty { say("  주제  \(s.topic)") }
            let units = s.unitIds.compactMap { id in f.units.first { $0.id == id }?.title }
            if !units.isEmpty {
                say("  단원")
                for u in units { say("    \(u)") }
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm", abstract: "아무것도 연결되지 않은 회차 지우기", discussion: """
            노트, 녹음, 출석, 자료, 단원이 연결된 회차는 지우지 않는다(종료 코드 4). 수업이 없던 날이면 --cancelled true로 휴강 표시한다.
            확인을 받는다.

            예시:
              folio session rm EC4207/9주차-3 --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<회차>. 같은 과목이면 둘째부터 회차만 써도 된다", valueName: "session"), completion: Complete.sessions) var sessions: [String]

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            guard let first = sessions.first else { throw CLIError(exit: .usage, message: "지울 회차를 주세요") }
            let (c, name) = try r.split(first)
            let ids = try ([name] + sessions.dropFirst().map { $0.contains("/") ? try r.split($0).1 : $0 }).map { try r.session($0, in: c).id }
            try perform(spec: SessionRemove(course: c.id, sessions: ids), g, ctx: ctx)
        }
    }
}

struct AttendanceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "attendance", abstract: "출결", subcommands: GeneratedCommands.attendance)
}
