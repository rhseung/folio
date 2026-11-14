import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation
import PDFKit

extension RecordingCommand {
    struct Transcript: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .recordingTranscriptAbstract),
            discussion: String(localized: .recordingTranscriptDiscussion(ReadingLimit.transcript)))
        @OptionGroup var g: GlobalOptions
        @Argument(
            help: ArgumentHelp(String(localized: .recordingTranscriptHelpRecording), valueName: "recording"), completion: Complete.sessions)
        var recording: String = ""
        @Option(help: ArgumentHelp(String(localized: .recordingTranscriptHelpFrom), valueName: "m:ss")) var from: String?
        @Option(help: ArgumentHelp(String(localized: .recordingTranscriptHelpTo), valueName: "m:ss")) var to: String?

        struct Line: Encodable {
            var at: String
            var text: String
        }

        struct Shown: Encodable {
            var recording: String
            var session: String?
            var duration: String
            var lines: [Line]
            var next: String?
        }

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(recording)
            let rec = try r.recording(name, in: c)
            let start = try from.map(Self.seconds), end = try to.map(Self.seconds)
            guard let transcript = c.store.transcript(of: rec), !transcript.lines.isEmpty else {
                throw CLIError(exit: .notFound, message: String(localized: .recordingTranscriptNone(rec.file)))
            }
            let (lines, next) = transcript.window(from: start, to: end)
            let clock = { (t: TimeInterval) in AppLink.clock(Int(t)) }
            let session = rec.sessionId.flatMap { id in c.file.sessions.first { $0.id == id } }.map {
                c.file.reference(of: $0, calendar: r.ctx.calendar)
            }
            let shown = Shown(
                recording: rec.file, session: session, duration: clock(rec.duration),
                lines: lines.map { Line(at: clock($0.start), text: $0.text) }, next: next.map(clock))
            if g.json { return try printJSON(shown) }

            let span = "\(clock(start ?? 0))–\(clock(end ?? rec.duration))"
            say(String(localized: .recordingTranscriptHeader(rec.file, shown.duration, span)).styled(.bold))
            if lines.isEmpty { say(String(localized: .recordingTranscriptEmpty).styled(.dim)) }
            for l in shown.lines { say("[\(l.at)]".styled(.dim) + " " + l.text) }
            if let next = shown.next {
                let ref = "\(c.code)/\((rec.file as NSString).lastPathComponent)"
                let line =
                    "folio recording transcript \(MaterialCommand.Read.quoted(ref)) --from \(next)" + (to.map { " --to \($0)" } ?? "")
                say(String(localized: .readingNext(line)).styled(.dim))
            }
        }

        static func seconds(_ written: String) throws -> TimeInterval {
            let link = AppLink(string: "folio://recording/\(UUID().uuidString)#t=\(written.trimmingCharacters(in: .whitespaces))")
            guard case .time(let s)? = link?.anchor else {
                throw CLIError(exit: .usage, message: String(localized: .recordingTranscriptBadTime(written)))
            }
            return TimeInterval(s)
        }
    }
}
