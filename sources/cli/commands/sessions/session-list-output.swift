import FolioActions
import FolioDomain
import Foundation

extension SessionList: QueryLines {
    func lines(_ sessions: [Session], _ r: Resolver) throws -> [[String]] {
        let c = try r.course(id: course)
        let f = c.file
        return sessions.map { s in
            [
                "\(c.code)/\(f.reference(of: s, calendar: r.ctx.calendar))", s.date.formatted(date: .numeric, time: .shortened),
                kindLabel(s) ?? "", f.subject(of: s) ?? "",
            ]
        }
    }

    func say(_ sessions: [Session], _ r: Resolver) throws {
        let c = try r.course(id: course)
        let f = c.file
        courseHeader(c, catalog: try? r.ctx.catalog())
        var t = Table(
            header: [
                String(localized: .sessionListHeaderSession), String(localized: .sessionListHeaderDate),
                String(localized: .sessionListHeaderKind), String(localized: .sessionListHeaderUnits),
                String(localized: .sessionListHeaderNotes),
            ], shrink: [3])
        for s in sessions {
            let notes = [
                s.roughNoteId.map { _ in String(localized: .sessionListRough) },
                s.reviewNoteId.map { _ in
                    s.reviewNoteUnfinished == true
                        ? String(localized: .sessionListReviewUnfinished) : String(localized: .sessionListReview)
                },
            ].compactMap { $0 }
            let cells = [
                f.reference(of: s, calendar: r.ctx.calendar), when(s.date, now: r.ctx.now, time: true, settings: r.settings),
                kindLabel(s).map { $0.toned(s.kind.tone) } ?? "", f.subject(of: s) ?? "", notes.joined(separator: " · "),
            ]
            t.rows.append(s.date < r.ctx.now ? cells.map { $0.styled(.dim) } : cells)
        }
        t.print()
        footer(sessions.count, hidden: all ? nil : String(localized: .sessionListHidden))
    }
}
