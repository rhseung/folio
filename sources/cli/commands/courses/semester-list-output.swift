import FolioActions
import FolioDomain
import Foundation

extension SemesterList: QueryLines {
    func lines(_ semesters: [Semester], _ r: Resolver) throws -> [[String]] {
        semesters.map { s in [s.folder?.name ?? s.id.uuidString, "\(s.year) \(s.term.rawValue)", span(s)] }
    }

    func say(_ semesters: [Semester], _ r: Resolver) throws {
        let current = try? r.currentSemester().id
        var t = Table(header: [
            String(localized: .semesterListHeaderSemester), String(localized: .semesterListHeaderName),
            String(localized: .semesterListHeaderSpan),
        ])
        for s in semesters {
            let cells = [s.folder?.name ?? s.source ?? String(localized: .semesterRecognized), "\(s.year) \(s.term.rawValue)", span(s)]
            t.rows.append(s.id == current ? cells.map { $0.styled(.bold) } : cells)
        }
        t.print()
        footer(semesters.count)
    }

    private func span(_ s: Semester) -> String {
        [s.start?.description, s.end?.description].map { $0 ?? "?" }.joined(separator: " – ")
    }
}
