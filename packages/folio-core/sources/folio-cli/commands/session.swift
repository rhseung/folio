import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct SessionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session", abstract: String(localized: .sessionAbstract),
        subcommands: [List.self, Show.self] + GeneratedCommands.session + [Progress.self, Remove.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .sessionListAbstract), discussion: String(localized: .sessionListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .sessionListHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .sessionListHelpAll))) var all = false
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = c.file
            let sessions = f.sessions.sorted { $0.date < $1.date }.filter { all || !$0.isCancelled }
            if g.json { return try printJSON(sessions) }
            if lines {
                for s in sessions { line(["\(c.code)/\(f.reference(of: s, calendar: r.ctx.calendar))", s.date.formatted(date: .numeric, time: .shortened), s.isCancelled ? String(localized: .sessionListCancelled) : "", s.topic]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: [String(localized: .sessionListHeaderSession), String(localized: .sessionListHeaderDate), String(localized: .sessionListCancelled), String(localized: .sessionListHeaderTopic), String(localized: .sessionListHeaderNotes)], shrink: [3])
            for s in sessions {
                let notes = [s.roughNoteId.map { _ in String(localized: .sessionListRough) }, s.reviewNoteId.map { _ in s.reviewNoteUnfinished == true ? String(localized: .sessionListReviewUnfinished) : String(localized: .sessionListReview) }].compactMap { $0 }
                let cells = [f.reference(of: s, calendar: r.ctx.calendar), when(s.date, now: r.ctx.now, time: true), s.isCancelled ? String(localized: .sessionListCancelled).toned : "", s.topic, notes.joined(separator: " · ")]
                t.rows.append(s.date < r.ctx.now ? cells.map { $0.styled(.dim) } : cells)
            }
            t.print()
            footer(sessions.count, hidden: all ? nil : String(localized: .sessionListHidden))
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .sessionShowAbstract), discussion: String(localized: .sessionShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .sessionShowHelpSession), valueName: "session"), completion: Complete.sessions) var session: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(session)
            let s = try r.session(name, in: c)
            if g.json { return try printJSON(s) }
            let f = c.file
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(f.title(of: s, calendar: r.ctx.calendar).styled(.bold))
            say(String(localized: .sessionShowDate(when(s.date, now: r.ctx.now, time: true))))
            if s.isCancelled { say(String(localized: .sessionShowCancelled)) }
            if let end = s.end(schedule: f.course.schedule, calendar: r.ctx.calendar) {
                say(String(localized: .sessionShowEnd(end.formatted(date: .omitted, time: .shortened))))
            }
            if !s.topic.isEmpty { say(String(localized: .sessionShowTopic(s.topic))) }
            // The slot's link counts too: that's the one the join button opens.
            if let link = s.link(schedule: f.course.schedule, calendar: r.ctx.calendar) { say(String(localized: .sessionShowLink(link.absoluteString))) }
            let units = s.unitIds.compactMap { id in f.units.first { $0.id == id }?.title }
            if !units.isEmpty {
                say(String(localized: .sessionShowUnits))
                for u in units { say("    \(u)") }
            }
            let materials = s.materials.compactMap { link in f.materials.first { $0.id == link.materialId }.map { ($0, link) } }
            if !materials.isEmpty {
                say(String(localized: .sessionShowMaterials))
                for (m, link) in materials {
                    let pages = link.pages.map { " p.\($0.lowerBound)\($0.count > 1 ? "-\($0.upperBound)" : "")" } ?? ""
                    say("    \((m.path as NSString).lastPathComponent)\(pages)")
                }
            }
        }
    }

    struct Progress: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .sessionProgressAbstract), discussion: String(localized: .sessionProgressDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .sessionShowHelpSession), valueName: "session"), completion: Complete.sessions) var session: String
        @Argument(help: ArgumentHelp(String(localized: .sessionProgressHelpRanges), valueName: "material:pages")) var ranges: [String]

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(session)
            let s = try r.session(name, in: c)
            guard !ranges.isEmpty else { throw CLIError(exit: .usage, message: String(localized: .sessionProgressMissing)) }
            let links = try ranges.map { arg in
                // The last colon: a file name may hold one, the pages never do.
                guard let colon = arg.lastIndex(of: ":") else { throw CLIError(exit: .usage, message: String(localized: .sessionProgressFormat(arg))) }
                let bounds = arg[arg.index(after: colon)...].split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
                guard (1...2).contains(bounds.count), let first = bounds.first ?? nil, let last = bounds.last ?? nil else {
                    throw CLIError(exit: .usage, message: String(localized: .sessionProgressFormat(arg)))
                }
                let m = try r.material(c.local(String(arg[..<colon])), in: c)
                return SessionMaterial(materialId: m.id, firstPage: first, lastPage: last)
            }
            try perform(spec: SessionProgress(course: c.id, session: s.id, ranges: links), g, ctx: ctx)
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm", abstract: String(localized: .sessionRmAbstract), discussion: String(localized: .sessionRmDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .sessionRmHelpSessions), valueName: "session"), completion: Complete.sessions) var sessions: [String]

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            guard let first = sessions.first else { throw CLIError(exit: .usage, message: String(localized: .sessionRmMissing)) }
            let (c, name) = try r.split(first)
            let ids = try ([name] + sessions.dropFirst().map { $0.contains("/") ? try r.split($0).1 : $0 }).map { try r.session($0, in: c).id }
            try perform(spec: SessionRemove(course: c.id, sessions: ids), g, ctx: ctx)
        }
    }
}

struct AttendanceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "attendance", abstract: String(localized: .attendanceAbstract), subcommands: GeneratedCommands.attendance)
}

struct RecordingCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "recording", abstract: String(localized: .recordingAbstract),
                                                    subcommands: GeneratedCommands.recording + [Retitle.self])

    struct Retitle: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .recordingRetitleAbstract), discussion: String(localized: .recordingRetitleDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .recordingRetitleHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let id = try course.map { try Resolver(ctx).course($0).id }
            let result = try perform(spec: RecordingRetitleLegacy(course: id), g, ctx: ctx)
            if !g.json, let batch = result.made { say(String(localized: .noteRetitleUndo(batch.uuidString)).styled(.dim)) }
        }
    }
}
