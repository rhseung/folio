import FolioActions
import FolioDomain
import Foundation
import Observation

/// Adding a session, or editing one: when it starts and ends, its topic and its meeting link.
@MainActor @Observable
final class SessionFormModel {
    let workspace: Workspace
    let courseId: UUID
    /// Nil while adding.
    let session: Session?
    var start: Date
    /// Minutes from the start day's midnight: a class ends on the day it starts. The view sets it through `setEnd`.
    var endMinute: Int
    var topic: String
    var link: String
    var cancelled = false
    private let initialEnd: Date?
    /// A session that never had an end (a date-only import) gets one only when the user picks it.
    private var endPicked = false

    init(workspace: Workspace, courseId: UUID, session: Session? = nil) {
        self.workspace = workspace
        self.courseId = courseId
        self.session = session
        let calendar = workspace.calendar
        let start = session?.date ?? calendar.date(byAdding: .hour, value: 18, to: calendar.startOfDay(for: workspace.now))!
        let schedule = workspace.course(courseId)?.file.course.schedule ?? []
        let end = session?.end(schedule: schedule, calendar: calendar)
        initialEnd = end
        self.start = start
        // A class off the timetable gets GIST's usual 75 minutes to start from.
        endMinute = Self.minute(of: end ?? start.addingTimeInterval(75 * 60), from: start, calendar: calendar)
        topic = session?.topic ?? ""
        link = session?.link ?? ""
    }

    var title: String {
        guard let session, let file = workspace.course(courseId)?.file else { return String(localized: .sessionsAdd) }
        return String(localized: .commonEditNamed(file.name(of: session)))
    }

    var confirm: String { String(localized: session == nil ? .commonAdd : .commonSave) }

    var calendar: Calendar { workspace.calendar }

    var end: Date { calendar.date(byAdding: .minute, value: endMinute, to: calendar.startOfDay(for: start))! }

    /// Moving the start keeps the class as long as it was.
    func setStart(_ date: Date) {
        let length = end.timeIntervalSince(start)
        start = date
        endMinute = Self.minute(of: date.addingTimeInterval(length), from: date, calendar: calendar)
    }

    func setEnd(_ minute: Int) {
        endMinute = minute
        endPicked = true
    }

    /// Why the form can't be saved, or a word about what saving does; nil when there's nothing to say.
    var note: String? {
        if end <= start { return String(localized: .sessionsEndBeforeStart) }
        if !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, OnlineLink.url(link) == nil { return String(localized: .sessionsLinkInvalid) }
        if let session, let file = workspace.course(courseId)?.file, movesWeek(session, file) { return String(localized: .sessionsRenameOnMove) }
        return nil
    }

    var disabled: Bool { end <= start || (!link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && OnlineLink.url(link) == nil) }

    func submit() {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session else {
            workspace.run(SessionAdd(course: courseId, date: start, end: end, topic: topic, link: link.isEmpty ? nil : link, cancelled: cancelled))
            return
        }
        // Only what changed. An end the timetable gives isn't stored, so editing the class times later still moves it;
        // a moved class keeps its length, which the action stores only when it leaves its slot.
        let endPatch: Patch<Date?> = endPicked || (initialEnd != nil && start != session.date) ? .set(end) : .keep
        workspace.run(SessionSet(course: courseId, session: session.id,
                                 date: start == session.date ? .keep : .set(start),
                                 end: endPatch,
                                 topic: topic == session.topic ? .keep : .set(topic),
                                 link: link == (session.link ?? "") ? .keep : .set(link.isEmpty ? nil : link)))
    }

    private func movesWeek(_ session: Session, _ file: CourseFile) -> Bool {
        guard start != session.date else { return false }
        let others = file.sessions.filter { $0.id != session.id }
        let termStart = workspace.semester(of: file.course)?.start
        let anchor = termStart?.date(in: calendar) ?? (others.map(\.date) + [start]).min()!
        return SessionPlanner.week(of: start, anchor: anchor, calendar: calendar) != session.week
    }

    private static func minute(of date: Date, from start: Date, calendar: Calendar) -> Int {
        let minutes = Int(date.timeIntervalSince(calendar.startOfDay(for: start)) / 60)
        return min(max(minutes, 0), 24 * 60 - 5)
    }
}
