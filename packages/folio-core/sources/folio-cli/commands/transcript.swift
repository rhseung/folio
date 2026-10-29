import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

/// Read-only: grades and credits are changed on the course (`folio course set`), the term on the semester.
struct TranscriptCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcript", abstract: "성적표: 학기별 과목, 학점, 평가 방식, 성적. 폴더 없는 과목의 기록",
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
                Row(semester: s.folder?.name ?? "인정학기", code: c.code, courseId: c.id, title: c.course.title, credits: c.course.credits,
                    gradingMode: c.course.gradingMode, grade: catalog.grade(c.course.finalGrade)?.symbol)
            }
        }
    }

    static func print(_ rows: [Row], semester: Bool) {
        var t = Table(header: (semester ? ["학기"] : []) + ["과목", "이름", "학점", "평가", "성적"], shrink: [semester ? 2 : 1])
        for x in rows {
            t.rows.append((semester ? [x.semester] : []) + [x.code, x.title, x.credits.formatted(), x.gradingMode.rawValue.toned, x.grade ?? "-"])
        }
        t.print()
        footer(rows.count)
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "모든 학기의 과목과 성적", discussion: """
            성적은 folio course set <과목> --grade로, 학점 합계와 GPA는 folio gpa로 본다.

            예시:
              folio transcript list
              folio transcript list --json
            """)
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let r = Resolver(try CLI.context(g))
            try GradesLock.require()
            let rows = try TranscriptCommand.rows(r, in: r.semesters)
            if g.json { return try printJSON(rows) }
            TranscriptCommand.print(rows, semester: true)
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "한 학기의 과목, 성적, 학기 GPA", discussion: """
            학기를 생략하면 이번 학기.

            예시:
              folio transcript show
              folio transcript show 2026-1
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("학기. 폴더 이름(2026-1) 또는 '2026 봄'", valueName: "semester"), completion: .custom(Complete.semesters)) var semester: String?

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let s = try r.semester(semester)
            try GradesLock.require()
            let rows = try TranscriptCommand.rows(r, in: [s])
            let summary = GPACalculator.semester(s, courses: try r.ctx.gist.allCourses(), catalog: try r.ctx.catalog())
            struct Out: Encodable { var courses: [Row]; var totalCredits: Double; var effectiveCredits: Double; var gpa: Double? }
            if g.json { return try printJSON(Out(courses: rows, totalCredits: summary.totalCredits, effectiveCredits: summary.effectiveCredits, gpa: summary.gpa)) }
            say((s.folder?.name ?? "인정학기").styled(.bold) + "  " + "총 \(summary.totalCredits.formatted())학점 · 유효 \(summary.effectiveCredits.formatted())학점 · GPA \(GPACalculator.label(summary.gpa))".styled(.dim))
            TranscriptCommand.print(rows, semester: false)
        }
    }
}
