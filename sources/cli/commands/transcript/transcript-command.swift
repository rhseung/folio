import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct TranscriptCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcript", abstract: String(localized: .transcriptAbstract),
        subcommands: [List.self, Show.self] + GeneratedCommands.transcript)

    struct Row: Encodable {
        var semester: String
        var code: String
        var courseId: UUID
        var title: String
        var credits: Double
        var gradingMode: GradingMode
        var grade: String?
    }

    static func rows(_ r: Resolver, in semesters: [Semester]) throws -> [Row] {
        let catalog = try r.ctx.catalog()
        return semesters.flatMap { s in
            r.courses.filter { $0.course.semesterId == s.id }.sorted { $0.code < $1.code }.map { c in
                Row(
                    semester: s.folder?.name ?? s.source ?? String(localized: .semesterRecognized), code: c.code, courseId: c.id,
                    title: c.course.title, credits: c.course.credits,
                    gradingMode: c.course.gradingMode, grade: catalog.grade(c.course.finalGrade)?.symbol)
            }
        }
    }

    static func print(_ rows: [Row], semester: Bool) {
        var t = Table(
            header: (semester ? [String(localized: .transcriptHeaderSemester)] : []) + [
                String(localized: .transcriptHeaderCourse), String(localized: .transcriptHeaderName),
                String(localized: .transcriptHeaderCredits), String(localized: .transcriptHeaderMode),
                String(localized: .transcriptHeaderGrade),
            ], shrink: [semester ? 2 : 1])
        for x in rows {
            t.rows.append(
                (semester ? [x.semester] : []) + [x.code, x.title, x.credits.formatted(), x.gradingMode.rawValue.toned, x.grade ?? "-"])
        }
        t.print()
        footer(rows.count)
    }
}
