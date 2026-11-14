import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct TranscriptCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcript", abstract: String(localized: .transcriptAbstract),
        subcommands: subcommandTypes)

    static func print(_ rows: [TranscriptRow], semester: Bool) {
        var t = Table(
            header: (semester ? [String(localized: .transcriptHeaderSemester)] : []) + [
                String(localized: .transcriptHeaderCourse), String(localized: .transcriptHeaderName),
                String(localized: .transcriptHeaderCredits), String(localized: .transcriptHeaderMode),
                String(localized: .transcriptHeaderGrade),
            ], shrink: [semester ? 2 : 1])
        for x in rows {
            t.rows.append(
                (semester ? [x.semester] : []) + [
                    x.code, x.title, x.credits.formatted(), x.gradingMode.rawValue.toned(x.gradingMode.tone), x.grade ?? "-",
                ])
        }
        t.print()
        footer(rows.count)
    }
}
