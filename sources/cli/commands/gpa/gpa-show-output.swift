import FolioActions
import FolioDomain
import Foundation

extension GPAShow: QueryOutput {
    func say(_ rows: [Row], _ r: Resolver) throws {
        var t = Table(header: [
            String(localized: .gpaHeaderSemester), String(localized: .gpaHeaderTotalCredits), String(localized: .gpaHeaderEffectiveCredits),
            "GPA",
        ])
        let semesters = rows.count - 2
        for (i, x) in rows.enumerated() {
            let cells = [x.name, x.totalCredits.formatted(), x.effectiveCredits.formatted(), GPACalculator.label(x.gpa)]
            t.rows.append(i >= semesters ? cells.map { $0.styled(.bold) } : cells)
        }
        t.print()
    }
}
