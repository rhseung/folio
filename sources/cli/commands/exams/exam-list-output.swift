import FolioActions
import FolioDomain
import Foundation

extension ExamList: QueryLines {
    func lines(_ linked: [QueryLinks<Exam>], _ r: Resolver) throws -> [[String]] {
        let exams = linked.map(\.item)
        let c = try r.course(id: course)
        return exams.map { e in
            ["\(c.code)/\(e.title)", e.title, e.start.map { $0.formatted(date: .numeric, time: .shortened) } ?? "", component(e, c.file)]
        }
    }

    func say(_ linked: [QueryLinks<Exam>], _ r: Resolver) throws {
        let exams = linked.map(\.item)
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
                c.file.scope(of: e).isEmpty ? "" : String(localized: .examListUnits(c.file.scope(of: e).count)),
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
