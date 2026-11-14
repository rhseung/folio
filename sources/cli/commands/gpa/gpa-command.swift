import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct GPACommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gpa", abstract: String(localized: .gpaAbstract), discussion: String(localized: .gpaDiscussion))
    @OptionGroup var g: GlobalOptions

    struct Row: Encodable {
        var name: String
        var totalCredits: Double
        var effectiveCredits: Double
        var gpa: Double?
    }

    func run() throws {
        let ctx = try CLI.context(g)
        try GradesLock.require()
        let catalog = try ctx.catalog()
        let courses = try ctx.gist.allCourses()
        let semesters = try ctx.transcript().semesters.sorted { $0.order < $1.order }
        let row = { (name: String, s: GPACalculator.Summary) in
            Row(name: name, totalCredits: s.totalCredits, effectiveCredits: s.effectiveCredits, gpa: s.gpa)
        }
        let rows =
            semesters.map {
                row(
                    $0.folder?.name ?? $0.source ?? String(localized: .semesterRecognized),
                    GPACalculator.semester($0, courses: courses, catalog: catalog))
            }
            + [
                row(String(localized: .gpaCumulative), GPACalculator.cumulative(semesters: semesters, courses: courses, catalog: catalog)),
                row(String(localized: .gpaMajor), GPACalculator.major(courses: courses, catalog: catalog)),
            ]
        if g.json { return try printJSON(rows) }
        var t = Table(header: [
            String(localized: .gpaHeaderSemester), String(localized: .gpaHeaderTotalCredits), String(localized: .gpaHeaderEffectiveCredits),
            "GPA",
        ])
        for (i, x) in rows.enumerated() {
            let cells = [x.name, x.totalCredits.formatted(), x.effectiveCredits.formatted(), GPACalculator.label(x.gpa)]
            t.rows.append(i >= semesters.count ? cells.map { $0.styled(.bold) } : cells)
        }
        t.print()
    }
}
