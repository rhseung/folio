import FolioActions
import FolioDomain
import Foundation

extension CourseGaps: QueryOutput {
    func say(_ items: [Item], _ r: Resolver) throws {
        guard !items.isEmpty else { return FolioCLI.say("✓".styled(.green) + " " + String(localized: .courseGapsNone)) }
        var t = Table(header: ["", String(localized: .courseGapsHeaderGap)], shrink: [1])
        for i in items {
            let c = try? r.course(id: i.course)
            t.rows.append([c.map { "●".course($0.color) + " " + $0.tag } ?? "", i.dangling ? i.summary.styled(.red) : i.summary])
        }
        t.print()
        footer(items.count)
    }
}
