import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

/// `folio add "선대 HW5 금 23:59"`: the app's quick-add line, read by the same `QuickAdd.parse` and saved by the same
/// `AssignmentAdd`. Written by hand rather than as an action: what it saves is `assignment add`, and the line is only
/// another way to fill that action's fields.
struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: String(localized: .addAbstract), discussion: String(localized: .addDiscussion))
    @OptionGroup var g: GlobalOptions
    @Argument(help: ArgumentHelp(String(localized: .addHelpLine), valueName: "line")) var line: String
    @Option(help: ArgumentHelp(String(localized: .addHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String?
    @Option(help: ArgumentHelp(String(localized: .addHelpDue), valueName: "when")) var due: Clearable<DateArg>?
    @Option(help: ArgumentHelp(String(localized: .addHelpRepeats))) var repeats: Clearable<AssignmentRepeat>?

    struct Read: Encodable {
        var course: String?
        var courseId: UUID?
        var title: String
        var due: Date?
        var repeats: AssignmentRepeat?
        var folder: String?
    }

    func run() throws {
        let ctx = try CLI.context(g)
        let r = Resolver(ctx)
        // The courses the line can name are the ones the app's quick add reads: this semester's.
        let current = (try? r.currentSemester()).map { s in r.courses.filter { $0.course.semesterId == s.id } } ?? []
        let read = QuickAdd.parse(line, courses: current.map(\.course), codes: (try? ctx.catalog().codes) ?? [], now: ctx.now, calendar: ctx.calendar)
        // The options are the chips: each one stands over what the line reads, and clearing the deadline clears the
        // repeat with it, as the deadline chip's clear button does.
        var picks = QuickAddPicks()
        if let course { picks.pickCourse(try r.course(course).id, over: read) }
        if let due { picks.pickDue(due.value?.date, over: read) }
        if let repeats {
            picks.pickRepeats(repeats.value, over: read)
        } else if case .clear? = due, read.repeats != nil {
            picks.pickRepeats(nil, over: read)
        }
        let parsed = picks.applied(to: read)
        let ref = parsed.courseId.flatMap { id in r.courses.first { $0.id == id } }
        let shown = Read(course: ref?.code, courseId: parsed.courseId, title: parsed.title, due: parsed.due, repeats: parsed.repeats,
                         folder: parsed.folderName.map { "\(CourseFolder.assignments.rawValue)/\($0)" })
        if !g.json { show(shown, ref: ref, now: ctx.now, calendar: ctx.calendar) }
        guard let id = parsed.courseId else {
            throw CLIError(exit: .notFound, message: String(localized: .addNoCourse(line)), candidates: current.map(\.code),
                           hints: [String(localized: .addNoCourseHint(line))])
        }
        guard !parsed.title.isEmpty else { throw CLIError(exit: .usage, message: String(localized: .addNoTitle(line))) }
        try perform(spec: AssignmentAdd(course: id, title: parsed.title, due: parsed.due, repeats: parsed.repeats), g, ctx: ctx, read: try JSONValue(shown))
    }

    func show(_ read: Read, ref: CourseRef?, now: Date, calendar: Calendar) {
        func row(_ label: String, _ value: String) { say("  " + label.padded(to: 4).styled(.dim) + "  " + value) }
        say(String(localized: .addRead).styled(.bold))
        row(String(localized: .addFieldCourse), ref.map { "●".course($0.color) + " " + $0.course.title + "  " + $0.code.styled(.dim) }
            ?? String(localized: .addUnread).styled(.red))
        row(String(localized: .addFieldTitle), read.title.isEmpty ? String(localized: .addUnread).styled(.red) : read.title)
        if let due = read.due {
            let day = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
            let deadline = CourseFile.deadline(due, calendar: calendar, locale: Locale(identifier: "ko_KR"))
            row(String(localized: .addFieldDue), (-1...14).contains(day) ? deadline + " · " + when(due, now: now, calendar: calendar) : deadline)
        } else {
            row(String(localized: .addFieldDue), String(localized: .addNoDue).styled(.dim))
        }
        if read.repeats == .weekly { row(String(localized: .addFieldRepeats), String(localized: .addWeekly)) }
        if let folder = read.folder { row(String(localized: .addFieldFolder), folder) }
    }
}
