import FolioActions
import FolioDomain
import Foundation

extension ExamList: QueryLines {
    func lines(_ exams: [Exam], _ r: Resolver) throws -> [[String]] {
        let c = try r.course(id: course)
        return exams.map { e in
            ["\(c.code)/\(e.title)", e.title, e.start.map { $0.formatted(date: .numeric, time: .shortened) } ?? "", component(e, c.file)]
        }
    }

    func say(_ exams: [Exam], _ r: Resolver) throws {
        let c = try r.course(id: course)
        courseHeader(c, catalog: try? r.ctx.catalog())
        var t = Table(
            header: [
                String(localized: .examListHeaderExam), String(localized: .examListHeaderTime),
                String(localized: .examListHeaderComponent), String(localized: .examListHeaderLocation),
                String(localized: .examListHeaderScope),
            ], shrink: [3])
        for e in exams {
            let cells = [
                e.title, e.start.map { when($0, now: r.ctx.now, time: true, settings: r.settings) } ?? "-", component(e, c.file),
                e.location,
                e.scopeUnitIds.isEmpty ? "" : String(localized: .examListUnits(e.scopeUnitIds.count)),
            ]
            t.rows.append((e.end ?? e.start).map { $0 < r.ctx.now } ?? false ? cells.map { $0.styled(.dim) } : cells)
        }
        t.print()
        footer(exams.count)
    }

    private func component(_ e: Exam, _ file: CourseFile) -> String {
        e.componentId.flatMap { id in file.components.first { $0.id == id }?.name } ?? ""
    }
}
