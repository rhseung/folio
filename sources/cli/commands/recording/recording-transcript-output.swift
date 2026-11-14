import FolioActions
import FolioDomain
import Foundation

extension RecordingTranscript: QueryOutput {
    func say(_ shown: Shown, _ r: Resolver) throws {
        let c = try r.course(id: course)
        let duration = c.file.recordings.first { $0.id == recording }?.duration ?? 0
        let clock = { (t: TimeInterval) in AppLink.clock(Int(t)) }
        let start = try from.map(Self.seconds), end = try to.map(Self.seconds)
        let span = "\(clock(start ?? 0))–\(clock(end ?? duration))"
        FolioCLI.say(String(localized: .recordingTranscriptHeader(shown.recording, shown.duration, span)).styled(.bold))
        if shown.lines.isEmpty { FolioCLI.say(String(localized: .recordingTranscriptEmpty).styled(.dim)) }
        for l in shown.lines { FolioCLI.say("[\(l.at)]".styled(.dim) + " " + l.text) }
        if let next = shown.next {
            let ref = "\(c.code)/\((shown.recording as NSString).lastPathComponent)"
            let line = "folio recording transcript \(MaterialCommand.Read.quoted(ref)) --from \(next)" + (to.map { " --to \($0)" } ?? "")
            FolioCLI.say(String(localized: .readingNext(line)).styled(.dim))
        }
    }
}
