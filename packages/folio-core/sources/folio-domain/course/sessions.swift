import Foundation

/// The unit of review and quizzes.
public struct Unit: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var title: String
    public var order: Int
    public var parentId: UUID?
    public var sessionIds: [UUID]
    public var examIds: [UUID]

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, title: String, order: Int, parentId: UUID? = nil) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.title = title
        self.order = order
        self.parentId = parentId
        self.sessionIds = []
        self.examIds = []
    }
}

/// A lecture file linked to a session, optionally only some pages.
public struct SessionMaterial: Codable, Sendable, Hashable {
    public var materialId: UUID
    public var firstPage: Int?
    public var lastPage: Int?

    public init(materialId: UUID, firstPage: Int? = nil, lastPage: Int? = nil) {
        self.materialId = materialId
        self.firstPage = firstPage
        self.lastPage = lastPage
    }
}

public struct Session: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var week: Int
    /// Order within the week, from 1.
    public var index: Int
    public var date: Date
    public var topic: String
    public var unitIds: [UUID]
    public var roughNoteId: UUID?
    public var reviewNoteId: UUID?
    public var inkIds: [UUID]
    public var materials: [SessionMaterial]
    /// Set only for a class off the weekly times (a makeup at 21:00, say); the rest end with their slot.
    public var end: Date?
    /// An online class's meeting link, pasted from the invite. Without one the class takes its slot's link.
    public var link: String?
    // Optional so course.json files from before it decode, and left out of the file unless set.
    private var noReview: Bool?
    // Same optional trick: notes from before it, and imported ones, count as written.
    private var reviewNoteDraft: Bool?
    // Same again: only a cancelled class carries the key.
    private var cancelled: Bool?

    /// The class didn't happen (a holiday, 휴강): it stays as a session but counts toward no attendance or review.
    public var isCancelled: Bool {
        get { cancelled ?? false }
        set { cancelled = newValue ? true : nil }
    }

    /// A class that covered nothing new (only grading, say): no review note is asked of it, and it doesn't restart
    /// the review cycle of units linked to it.
    public var skipsReview: Bool {
        get { noReview ?? false }
        set { noReview = newValue ? true : nil }
    }

    /// The review note exists but isn't written yet: making it from the template doesn't count as writing it.
    public var reviewNoteUnfinished: Bool {
        get { reviewNoteId != nil && (reviewNoteDraft ?? false) }
        set { reviewNoteDraft = newValue ? true : nil }
    }

    public init(id: UUID = UUID(), device: DeviceID, at now: Date, week: Int, index: Int, date: Date) {
        self.id = id
        self.createdAt = now
        self.updatedAt = now
        self.updatedBy = device
        self.week = week
        self.index = index
        self.date = date
        self.topic = ""
        self.unitIds = []
        self.inkIds = []
        self.materials = []
    }

    /// `9주차-2`; also the default title of the session's rough note and recording. A recitation is numbered like any
    /// other class. Not stored, so names already written into notes and recordings stay as they were.
    public func name(among sessions: [Session]) -> String { "\(week)주차-\(index)" }

    public func needsReviewNote(at now: Date) -> Bool { !isCancelled && !skipsReview && date <= now && (reviewNoteId == nil || reviewNoteUnfinished) }
}

/// Sessions are made as classes happen, not ahead for the whole term: the weekly schedule only suggests the next lecture,
/// and anything off it (a recitation, a makeup) is added by hand.
public enum SessionPlanner {
    public struct Suggestion: Sendable, Equatable {
        public var date: Date
        public var end: Date
        public var room: String
        public var link: String?
    }

    /// The lecture under way or next on the schedule, within the coming week, that no session stands for yet. A session
    /// starting at that time (or a date-only one that day) stands for it even when cancelled, so a 휴강 moves on to the next.
    /// Exam weeks (counted from `start`) hold no lectures, nor does a class time an exam overlaps.
    public static func suggestion(schedule: [ClassTime], sessions: [Session], from start: LocalDate?, to end: LocalDate?,
                                  examWeeks: Set<Int> = [], exams: [DateInterval] = [], now: Date, calendar: Calendar) -> Suggestion? {
        let today = calendar.startOfDay(for: now)
        let anchor = start?.date(in: calendar)
        for offset in 0..<8 {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let local = LocalDate(day, in: calendar)
            if let start, local < start { continue }
            if let end, local > end { return nil }
            if let anchor, examWeeks.contains(week(of: day, anchor: anchor, calendar: calendar)) { continue }
            let weekday = calendar.isoWeekday(of: day)
            for slot in schedule.filter({ $0.weekday == weekday }).sorted(by: { $0.startMinute < $1.startMinute }) {
                let begin = calendar.date(byAdding: .minute, value: slot.startMinute, to: day)!
                let finish = calendar.date(byAdding: .minute, value: slot.endMinute, to: day)!
                guard finish > now, !exams.contains(where: { $0.start < finish && $0.end > begin }) else { continue }
                let taken = sessions.contains { $0.date == begin || $0.date == day }
                if !taken { return Suggestion(date: begin, end: finish, room: slot.room, link: slot.link) }
            }
        }
        return nil
    }

    /// Every class the weekly schedule puts on `day`, in order, for a course that keeps no sessions (a colloquium kept
    /// only in transcript.json). Days outside the term and exam weeks hold none, as for `suggestion`.
    public static func meetings(schedule: [ClassTime], on day: LocalDate, from start: LocalDate?, to end: LocalDate?,
                                examWeeks: Set<Int> = [], calendar: Calendar) -> [Suggestion] {
        guard let date = day.date(in: calendar), start.map({ $0 <= day }) ?? true, end.map({ day <= $0 }) ?? true else { return [] }
        if let anchor = start?.date(in: calendar), examWeeks.contains(week(of: date, anchor: anchor, calendar: calendar)) { return [] }
        let weekday = calendar.isoWeekday(of: date)
        return schedule.filter { $0.weekday == weekday }.sorted { $0.startMinute < $1.startMinute }.map { slot in
            Suggestion(date: calendar.date(byAdding: .minute, value: slot.startMinute, to: date)!,
                       end: calendar.date(byAdding: .minute, value: slot.endMinute, to: date)!, room: slot.room, link: slot.link)
        }
    }

    /// A new session at `date`. Its week counts Monday-based weeks from the term's start (or, without one, from the
    /// earliest session); it goes last in its week, so names already given to that week's sessions don't shift.
    public static func session(at date: Date, sessions: [Session], termStart: LocalDate?,
                               calendar: Calendar, device: DeviceID, now: Date) -> Session {
        let anchor = termStart?.date(in: calendar) ?? sessions.map(\.date).min() ?? date
        let week = week(of: date, anchor: anchor, calendar: calendar)
        let index = (sessions.filter { $0.week == week }.map(\.index).max() ?? 0) + 1
        return Session(device: device, at: now, week: week, index: index, date: date)
    }

    /// Monday-based weeks, the week holding `anchor` being the first.
    public static func week(of date: Date, anchor: Date, calendar: Calendar) -> Int {
        let firstMonday = calendar.startOfWeek(containing: anchor)
        return max(1, calendar.dateComponents([.day], from: firstMonday, to: calendar.startOfDay(for: date)).day! / 7 + 1)
    }
}

extension CourseFile {
    /// Sessions made ahead of time that nothing has touched yet: in the future, not cancelled, and with no topic, end,
    /// link, note, ink, material, unit, attendance or recording. An end or link is a makeup someone set up on purpose. `notedSessions` are those a note's frontmatter points to.
    public func untouchedFutureSessions(now: Date, notedSessions: Set<UUID>) -> [Session] {
        sessions.filter { s in
            s.date > now && !s.isCancelled && s.topic.isEmpty && s.end == nil && s.link == nil && isUnlinked(s, notedSessions: notedSessions)
        }
    }

    /// Attendance of classes that have begun. A 결석 or 공결 marked ahead counts toward the caps only from its class's
    /// start, so the grade cap and the one-away warning don't move before the class happens.
    public func heldAttendance(at now: Date) -> [Attendance] {
        attendance.filter { a in sessions.first { $0.id == a.sessionId }.map { $0.date <= now && !$0.isCancelled } ?? true }
    }

    /// Nothing points at the session: no note, ink, material, unit, attendance or recording. Only such a session is
    /// deleted, since removing one that something points at would leave that link dangling.
    public func isUnlinked(_ s: Session, notedSessions: Set<UUID>) -> Bool {
        s.roughNoteId == nil && s.reviewNoteId == nil && s.inkIds.isEmpty && s.materials.isEmpty && s.unitIds.isEmpty
            && !notedSessions.contains(s.id)
            && !units.contains { $0.sessionIds.contains(s.id) }
            && !materials.contains { $0.sessionIds.contains(s.id) }
            && !attendance.contains { $0.sessionId == s.id }
            && !recordings.contains { $0.sessionId == s.id }
    }
}

extension LocalDate {
    public func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public init(_ date: Date, in calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)!
    }
}

extension Session {
    /// The weekly slot the class starts in, if any.
    public func slot(in schedule: [ClassTime], calendar: Calendar) -> ClassTime? {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let weekday = calendar.isoWeekday(of: date)
        return schedule.first { $0.weekday == weekday && $0.startMinute == minute }
    }

    /// When the class ends: its own end, else from the weekly slot it starts in. Nil when neither (a date-only import).
    public func end(schedule: [ClassTime], calendar: Calendar) -> Date? {
        if let end = self.end { return end }
        guard let slot = slot(in: schedule, calendar: calendar) else { return nil }
        return date.addingTimeInterval(TimeInterval((slot.endMinute - slot.startMinute) * 60))
    }

    /// When the class is taken to end, for a session that doesn't say: the course's usual class from its start, else
    /// `classMinutes` from the settings. One answer for the form, the join button and the day ribbon.
    public func expectedEnd(schedule: [ClassTime], classMinutes: Int, calendar: Calendar) -> Date {
        end(schedule: schedule, calendar: calendar) ?? date.addingTimeInterval(TimeInterval((schedule.usualMinutes ?? classMinutes) * 60))
    }

    /// The meeting to join: the session's own link, else its slot's, so a course held online needs the link only once.
    public func link(schedule: [ClassTime], calendar: Calendar) -> URL? {
        (self.link ?? slot(in: schedule, calendar: calendar)?.link).flatMap(OnlineLink.url)
    }

    /// Keeps an end only when the slot doesn't already give it, so changing the class times later still moves the class's end.
    public mutating func setEnd(_ end: Date?, schedule: [ClassTime], calendar: Calendar) {
        self.end = nil
        if let end, end != self.end(schedule: schedule, calendar: calendar) { self.end = end }
    }
}

extension CourseFile {
    /// Moves a session to `date`. Another week makes it the last of that week, as a new session would be; its name
    /// changes then, but names already written into notes and recordings stay. An end of its own moves with it.
    public mutating func reschedule(_ id: UUID, to date: Date, termStart: LocalDate?, calendar: Calendar) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        let others = sessions.filter { $0.id != id }
        let week = week(of: date, moving: id, termStart: termStart, calendar: calendar)
        if week != sessions[i].week {
            sessions[i].week = week
            sessions[i].index = (others.filter { $0.week == week }.map(\.index).max() ?? 0) + 1
        }
        if let end = sessions[i].end { sessions[i].end = end.addingTimeInterval(date.timeIntervalSince(sessions[i].date)) }
        sessions[i].date = date
    }
}

extension CourseFile {
    /// The week session `id` lands in when moved to `date`: counted from the term's start, or without one from the
    /// earliest of the other sessions and `date`.
    public func week(of date: Date, moving id: UUID, termStart: LocalDate?, calendar: Calendar) -> Int {
        let anchor = termStart?.date(in: calendar) ?? (sessions.filter { $0.id != id }.map(\.date) + [date]).min()!
        return SessionPlanner.week(of: date, anchor: anchor, calendar: calendar)
    }
}

/// A meeting link as pasted from an invite (Zoom, Meet, Teams, ...).
extension [ClassTime] {
    /// The course's usual class in minutes: its most common slot length, the longer on a tie, so a makeup for a two-hour
    /// lab runs two hours. Nil without class times.
    public var usualMinutes: Int? {
        let counts = Dictionary(map { $0.endMinute - $0.startMinute }.filter { $0 > 0 }.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }
}

public enum OnlineLink {
    /// What a link field stores: trimmed, and nil when nothing is left, so a stray space neither lights the link up
    /// nor trips the rule with a field that looks empty.
    public static func stored(_ text: String?) -> String? {
        text.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The web address in `text`, with `https://` added when it was pasted without one. Nil for anything that isn't
    /// one, which the rules refuse, so a typo never becomes a button that opens nothing.
    public static func url(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), host.contains(".") else { return nil }
        return url
    }

    /// Zoom's own scheme for a `zoom.us/j/<id>` link. The web link opens a browser tab that asks before handing over
    /// to the app; this goes to the app at once. Nil for anything else, which opens as it is.
    public static func appURL(_ url: URL) -> URL? {
        guard let host = url.host()?.lowercased(), host == "zoom.us" || host.hasSuffix(".zoom.us") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == "j", parts[1].allSatisfy(\.isNumber) else { return nil }
        var app = URLComponents()
        app.scheme = "zoommtg"
        app.host = "zoom.us"
        app.path = "/join"
        let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pwd" }?.value
        app.queryItems = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: parts[1])]
            + (pwd.map { [URLQueryItem(name: "pwd", value: $0)] } ?? [])
        return app.url
    }
}

extension Calendar {
    /// 1 = Monday ... 7 = Sunday, regardless of the calendar's locale settings.
    public func isoWeekday(of date: Date) -> Int {
        (component(.weekday, from: date) + 5) % 7 + 1
    }

    public func startOfWeek(containing date: Date) -> Date {
        self.date(byAdding: .day, value: -(isoWeekday(of: date) - 1), to: startOfDay(for: date))!
    }
}

extension Unit {
    /// A lab is a unit titled by its number, `Lab04 Thin-layer chromatography`; the lab session, report and manual
    /// link to it. Nil for any other unit.
    public var labNumber: Int? {
        title.prefixMatch(of: /(?i)lab\s*(\d{1,3})(?!\d)/).flatMap { Int($0.1) }
    }

    /// The experiment's name after its number: `Thin-layer chromatography`.
    public var labTitle: String {
        guard let m = title.prefixMatch(of: /(?i)lab\s*\d{1,3}[\s:._-]*/) else { return title }
        return String(title[m.range.upperBound...])
    }
}

extension CourseFile {
    /// Experiment name -> its `Lab<NN>` number, from the lab units.
    public var labNumbers: [String: Int] {
        Dictionary(units.compactMap { u in u.labNumber.map { (u.labTitle, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    /// `Lab<NN>` number -> the week of the first session linked to that lab's unit.
    public var labWeeks: [Int: Int] {
        Dictionary(units.compactMap { u in
            guard let n = u.labNumber, let first = sessions.filter({ u.sessionIds.contains($0.id) }).min(by: { $0.date < $1.date }) else { return nil }
            return (n, first.week)
        }, uniquingKeysWith: { a, _ in a })
    }

    /// Links the session to experiment `number`'s unit, making `Lab<NN> <topic>` at the top level when there is none,
    /// so the parts of a two-session experiment share one unit. `id` is the new unit's.
    public mutating func linkLab(_ number: Int, session: UUID, topic: String, id: UUID = UUID(), device: DeviceID, at now: Date) {
        let unit = units.first { $0.labNumber == number }?.id ?? {
            let title = [AssignmentKind.lab.folderName(number), topic].filter { !$0.isEmpty }.joined(separator: " ")
            units.append(Unit(id: id, device: device, at: now, title: title, order: UnitTree.nextOrder(under: nil, in: units)))
            return id
        }()
        if !units.contains(where: { $0.id == unit && $0.sessionIds.contains(session) }) { toggle(session: session, unit: unit) }
    }
}

extension CourseFile {
    public func name(of session: Session) -> String { session.name(among: sessions) }

    /// A past class still owing its review note: not when the session or the whole course is left out of review.
    public func needsReviewNote(_ session: Session, at now: Date) -> Bool {
        course.reviews != false && session.needsReviewNote(at: now)
    }

    /// A class held and reviewed that no unit covers: its review never reaches the unit queue until one is linked.
    public func needsUnits(_ session: Session, at now: Date) -> Bool {
        course.reviews != false && !session.isCancelled && !session.skipsReview && session.date <= now
            && !units.contains { $0.sessionIds.contains(session.id) }
    }

    /// `units` linked to the session, in outline order.
    public func units(of session: Session) -> [Unit] {
        UnitTree.outline(units).map(\.unit).filter { $0.sessionIds.contains(session.id) }
    }

    /// `9주차-1 · 그래프의 정의`, or the name alone without a topic.
    public func title(of session: Session) -> String {
        session.topic.isEmpty ? name(of: session) : "\(name(of: session)) · \(session.topic)"
    }
}

extension CourseFile {
    /// Drops every session's link to a deleted note, so no session claims a rough or review note that is gone.
    public mutating func forgetNote(_ id: UUID) {
        for i in sessions.indices {
            if sessions[i].roughNoteId == id { sessions[i].roughNoteId = nil }
            if sessions[i].reviewNoteId == id {
                sessions[i].reviewNoteId = nil
                sessions[i].reviewNoteUnfinished = false
            }
        }
    }

    /// Makes the note `session`'s rough or review note, in place of the one it had; the note leaves any session it
    /// was linked to before. Other kinds aren't a session's note, so they only unlink.
    public mutating func linkNote(_ id: UUID, to session: UUID?, as kind: NoteKind) {
        forgetNote(id)
        guard let session, let i = sessions.firstIndex(where: { $0.id == session }) else { return }
        switch kind {
        case .rough: sessions[i].roughNoteId = id
        case .review: sessions[i].reviewNoteId = id
        default: break
        }
    }
}
