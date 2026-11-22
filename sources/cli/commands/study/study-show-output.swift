import FolioActions
import FolioDomain
import Foundation

extension StudyShow: QueryOutput {
    func say(_ out: Summary, _ r: Resolver) throws {
        courseHeader(try r.course(id: course), catalog: try? r.ctx.catalog())
        var units = Table(
            header: [
                String(localized: .studyShowHeaderUnit), String(localized: .studyShowHeaderState),
                String(localized: .studyShowHeaderProblems), String(localized: .studyShowHeaderCards),
                String(localized: .studyShowHeaderPages),
            ], shrink: [0])
        for u in out.units {
            let state = (ReadinessState(rawValue: u.state)?.label ?? u.state) + (u.score.map { " \(Int(($0 * 100).rounded()))" } ?? "")
            units.rows.append([
                String(repeating: "  ", count: u.depth) + u.title + (u.done ? " ✓" : ""), state,
                "\(u.problemsSolved)/\(u.problemsTotal)" + (u.wrong > 0 ? " " + String(localized: .studyShowWrong(u.wrong)) : ""),
                u.cardsTotal > 0 ? "\(u.cardsTotal - u.cardsUnknown)/\(u.cardsTotal)" : "",
                u.pagesTotal > 0 ? "\(u.pagesSeen)/\(u.pagesTotal)" : "",
            ])
        }
        units.print()
        guard !out.wrong.isEmpty else { return }
        FolioCLI.say("")
        FolioCLI.say(String(localized: .studyShowSectionWrong).styled(.bold, .cyan))
        let wrong = Table(
            header: ["", "", ""],
            rows: out.wrong.map {
                [
                    "\($0.set) \($0.number)", $0.recheck ? String(localized: .studyShowRecheck) : String(localized: .studyShowOpen),
                    $0.since.styled(.dim),
                ]
            })
        wrong.render().dropFirst().forEach { FolioCLI.say($0) }
    }
}
