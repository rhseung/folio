import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

/// A lecture, the usual kind, goes unsaid.
private func kindLabel(_ s: Session) -> String? {
    switch s.kind {
    case .lecture: nil
    case .cancelled: String(localized: .sessionListCancelled)
    case .makeup: String(localized: .sessionListMakeup)
    }
}

struct SessionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session", abstract: String(localized: .sessionAbstract),
        subcommands: [List.self, Show.self] + GeneratedCommands.session)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .sessionListAbstract), discussion: String(localized: .sessionListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .sessionListHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Flag(help: ArgumentHelp(String(localized: .sessionListHelpAll))) var all = false
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = c.file
            let sessions = f.sessions.sorted { $0.date < $1.date }.filter { all || !$0.isCancelled }
            if g.json { return try printJSON(sessions) }
            if lines {
                for s in sessions {
                    line([
                        "\(c.code)/\(f.reference(of: s, calendar: r.ctx.calendar))", s.date.formatted(date: .numeric, time: .shortened),
                        kindLabel(s) ?? "", f.subject(of: s) ?? "",
                    ])
                }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(
                header: [
                    String(localized: .sessionListHeaderSession), String(localized: .sessionListHeaderDate),
                    String(localized: .sessionListHeaderKind), String(localized: .sessionListHeaderUnits),
                    String(localized: .sessionListHeaderNotes),
                ], shrink: [3])
            for s in sessions {
                let notes = [
                    s.roughNoteId.map { _ in String(localized: .sessionListRough) },
                    s.reviewNoteId.map { _ in
                        s.reviewNoteUnfinished == true
                            ? String(localized: .sessionListReviewUnfinished) : String(localized: .sessionListReview)
                    },
                ].compactMap { $0 }
                let cells = [
                    f.reference(of: s, calendar: r.ctx.calendar), when(s.date, now: r.ctx.now, time: true),
                    kindLabel(s).map { s.isCancelled ? $0.toned : $0 } ?? "", f.subject(of: s) ?? "", notes.joined(separator: " · "),
                ]
                t.rows.append(s.date < r.ctx.now ? cells.map { $0.styled(.dim) } : cells)
            }
            t.print()
            footer(sessions.count, hidden: all ? nil : String(localized: .sessionListHidden))
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .sessionShowAbstract), discussion: String(localized: .sessionShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .sessionShowHelpSession), valueName: "session"), completion: Complete.sessions)
        var session: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(session)
            let s = try r.session(name, in: c)
            if g.json { return try printJSON(s) }
            let f = c.file
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(f.title(of: s, calendar: r.ctx.calendar).styled(.bold))
            say(String(localized: .sessionShowDate(when(s.date, now: r.ctx.now, time: true))))
            switch s.kind {
            case .cancelled: say(String(localized: .sessionShowCancelled))
            case .makeup: say(String(localized: .sessionShowMakeup))
            case .lecture: break
            }
            if let end = s.end(schedule: f.course.schedule, calendar: r.ctx.calendar) {
                say(String(localized: .sessionShowEnd(end.formatted(date: .omitted, time: .shortened))))
            }
            // The slot's link counts too: that's the one the join button opens.
            if let link = s.link(schedule: f.course.schedule, calendar: r.ctx.calendar) {
                say(String(localized: .sessionShowLink(link.absoluteString)))
            }
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
}

struct AttendanceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attendance", abstract: String(localized: .attendanceAbstract), subcommands: GeneratedCommands.attendance)
}

struct RecordingCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recording", abstract: String(localized: .recordingAbstract),
        subcommands: [Transcript.self] + GeneratedCommands.recording)

}
