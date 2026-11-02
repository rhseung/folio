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
    /// The end is stored only when the user picks it or a class moves off the timetable; otherwise the slot keeps
    /// giving it, so editing the class times later still moves it.
    private var endPicked = false

    init(workspace: Workspace, courseId: UUID, session: Session? = nil) {
        self.workspace = workspace
        self.courseId = courseId
        self.session = session
        let calendar = workspace.calendar
        let start = session?.date ?? calendar.date(byAdding: .hour, value: 18, to: calendar.startOfDay(for: workspace.now))!
        let schedule = workspace.course(courseId)?.file.course.schedule ?? []
        // A class being added has no session yet; a stand-in at its start asks the same question the join button does.
        let end = (session ?? Session(device: workspace.device, at: start, week: 1, index: 1, date: start))
            .expectedEnd(schedule: schedule, classMinutes: workspace.settings.classMinutes, calendar: calendar)
        self.start = start
        endMinute = Self.minute(of: end, from: start, calendar: calendar)
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

    private var schedule: [ClassTime] { workspace.course(courseId)?.file.course.schedule ?? [] }

    /// The timetable slot a class starting at `date` falls in, if any.
    private func slot(at date: Date) -> ClassTime? {
        Session(device: workspace.device, at: date, week: 1, index: 1, date: date).slot(in: schedule, calendar: calendar)
    }

    /// Onto a timetable slot the class ends with the slot, unless an end was picked; elsewhere it keeps its length.
    func setStart(_ date: Date) {
        let length = end.timeIntervalSince(start)
        start = date
        if !endPicked, let slot = slot(at: date) {
            endMinute = slot.endMinute
        } else {
            endMinute = Self.minute(of: date.addingTimeInterval(length), from: date, calendar: calendar)
        }
    }

    func setEnd(_ minute: Int) {
        endMinute = minute
        endPicked = true
    }

    /// Why the form can't be saved, from the same rules every save is checked by, or else a word about what saving
    /// does; nil when there's nothing to say.
    var note: String? {
        if let refusal { return refusal }
        if let session, let file = workspace.course(courseId)?.file, movesWeek(session, file) { return String(localized: .sessionsRenameOnMove) }
        return nil
    }

    var disabled: Bool { refusal != nil }

    private var refusal: String? {
        if let edit { workspace.refusal(edit) } else { workspace.refusal(add) }
    }

    func submit() {
        if let edit { workspace.run(edit) } else { workspace.run(add) }
    }

    private var storedLink: String? { OnlineLink.stored(link) }

    private var add: SessionAdd {
        SessionAdd(course: courseId, date: start, end: end, topic: topic, link: storedLink, cancelled: cancelled)
    }

    /// Only what changed; nil while adding.
    private var edit: SessionSet? {
        guard let session else { return nil }
        return SessionSet(course: courseId, session: session.id,
                          date: start == session.date ? .keep : .set(start),
                          end: endPatch(session),
                          topic: topic == session.topic ? .keep : .set(topic),
                          link: storedLink == session.link ? .keep : .set(storedLink))
    }

    /// Saves the end the form shows. Unmoved and unpicked, the end stays as it is. Moved, the form's end goes to the
    /// action, which drops it again when it is the new slot's own, so the slot keeps giving it; a class with no end
    /// at all (a date-only import) gets none.
    private func endPatch(_ session: Session) -> Patch<Date?> {
        if endPicked { return .set(end) }
        guard start != session.date else { return .keep }
        return slot(at: start) != nil || session.end(schedule: schedule, calendar: calendar) != nil ? .set(end) : .keep
    }

    private func movesWeek(_ session: Session, _ file: CourseFile) -> Bool {
        start != session.date
            && file.week(of: start, moving: session.id, termStart: workspace.semester(of: file.course)?.start, calendar: calendar) != session.week
    }

    private static func minute(of date: Date, from start: Date, calendar: Calendar) -> Int {
        let minutes = Int(date.timeIntervalSince(calendar.startOfDay(for: start)) / 60)
        return min(max(minutes, 0), 24 * 60 - 5)
    }
}
