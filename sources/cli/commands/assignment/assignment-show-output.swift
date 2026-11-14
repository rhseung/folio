import FolioActions
import FolioDomain
import Foundation

extension AssignmentShow: QueryOutput {
    func say(_ a: Assignment, _ r: Resolver) throws {
        let c = try r.course(id: course)
        let f = c.file
        courseHeader(c, catalog: try? r.ctx.catalog())
        FolioCLI.say(a.title.styled(.bold))
        if let due = a.due {
            FolioCLI.say(String(localized: .assignmentShowDue(when(due, now: r.ctx.now, time: true, settings: r.settings))))
        }
        FolioCLI.say(String(localized: .assignmentShowStatus(a.status.rawValue.toned(a.status.tone))))
        if let repeats = a.repeats { FolioCLI.say(String(localized: .assignmentShowRepeats(repeats.label))) }
        if !a.memo.isEmpty { FolioCLI.say(String(localized: .assignmentShowMemo(a.memo))) }
        let scores = f.scores.filter { $0.assignmentId == a.id }
        if !scores.isEmpty {
            FolioCLI.say(String(localized: .assignmentShowScores))
            for s in scores {
                let comp = f.components.first { $0.id == s.componentId }?.name ?? ""
                FolioCLI.say("    \(comp)  \(GradesLock.masked("\(s.score.formatted())/\(s.max.formatted())"))")
            }
        }
    }
}
