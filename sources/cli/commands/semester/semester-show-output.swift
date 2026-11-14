import FolioActions
import FolioDomain
import Foundation

extension SemesterShow: QueryOutput {
    func say(_ s: Semester, _ r: Resolver) throws {
        FolioCLI.say(
            (s.folder?.name ?? s.source ?? String(localized: .semesterRecognized)).styled(.bold)
                + "  \(s.year) \(s.term.rawValue)".styled(.dim))
        FolioCLI.say(String(localized: .semesterShowStart(s.start?.description ?? "-")))
        FolioCLI.say(String(localized: .semesterShowEnd(s.end?.description ?? "-")))
        if let w = s.midtermWeek { FolioCLI.say(String(localized: .semesterShowMidterm(w))) }
        if let w = s.finalWeek { FolioCLI.say(String(localized: .semesterShowFinal(w))) }
        let courses = r.courses.filter { $0.course.semesterId == s.id }
        if !courses.isEmpty {
            FolioCLI.say(String(localized: .semesterShowCourses))
            for c in courses { FolioCLI.say("    " + "●".course(c.color) + " \(c.tag) \(c.course.title)") }
        }
    }
}
