import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension SemesterCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .semesterShowAbstract), discussion: String(localized: .semesterShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(
            help: ArgumentHelp(String(localized: .semesterShowHelpSemester), valueName: "semester"), completion: .custom(Complete.semesters)
        ) var semester: String?

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let s = try r.semester(semester)
            if g.json { return try printJSON(s) }
            say(
                (s.folder?.name ?? s.source ?? String(localized: .semesterRecognized)).styled(.bold)
                    + "  \(s.year) \(s.term.rawValue)".styled(.dim))
            say(String(localized: .semesterShowStart(s.start?.description ?? "-")))
            say(String(localized: .semesterShowEnd(s.end?.description ?? "-")))
            if let w = s.midtermWeek { say(String(localized: .semesterShowMidterm(w))) }
            if let w = s.finalWeek { say(String(localized: .semesterShowFinal(w))) }
            let courses = r.courses.filter { $0.course.semesterId == s.id }
            if !courses.isEmpty {
                say(String(localized: .semesterShowCourses))
                for c in courses { say("    " + "●".course(c.color) + " \(c.tag) \(c.course.title)") }
            }
        }
    }
}
