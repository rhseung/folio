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
    // Optional so course.json files from before it decode, and left out of the file while the unit has none.
    private var lectures: [UnitPages]?

    /// Pages of lecture files that belong to the unit (#321). Kept on the unit, not the file: a unit runs across
    /// several lecture files and a file holds several units.
    public var lecturePages: [UnitPages] {
        get { lectures ?? [] }
        set { lectures = newValue.isEmpty ? nil : newValue }
    }

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
    public var date: Date
    // A `topic` key older files carry is kept as an unknown field: what a class covered is its units now (#336).
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
    // Same again: only a cancelled class carries its key, and only a makeup the other. Two flags rather than one
    // `kind` key, so every file from before the makeup reads as it was (#338).
    private var cancelled: Bool?
    private var makeup: Bool?
    // And again: only a class whose wrap-up was saved carries it.
    private var wrappedUp: Bool?

    /// 강의, 휴강 or 보강. A makeup is held like any lecture (attendance, review, wrap-up); it only says the class was
    /// added to make up for another.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case lecture, cancelled, makeup
    }

    public var kind: Kind {
        get { cancelled == true ? .cancelled : makeup == true ? .makeup : .lecture }
        set {
            cancelled = newValue == .cancelled ? true : nil
            makeup = newValue == .makeup ? true : nil
        }
    }

    /// The class didn't happen (a holiday, 휴강): it stays as a session but counts toward no attendance or review.
    /// Clearing it leaves a lecture.
    public var isCancelled: Bool {
        get { kind == .cancelled }
        set { if newValue { kind = .cancelled } else if kind == .cancelled { kind = .lecture } }
    }

    /// The class's wrap-up was saved: what it left empty was left so on purpose, and present needs no entry of its
    /// own, so without this a class attended in person would be asked about forever.
    public var isWrappedUp: Bool {
        get { wrappedUp ?? false }
        set { wrappedUp = newValue ? true : nil }
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

    public init(id: UUID = UUID(), device: DeviceID, at now: Date, week: Int, date: Date) {
        self.id = id
        self.createdAt = now
        self.updatedAt = now
        self.updatedBy = device
        self.week = week
        self.date = date
        self.unitIds = []
        self.inkIds = []
        self.materials = []
    }

    /// By date; two classes at the same time (date-only imports) keep the order they were made in, so names don't flip.
    public static func inOrder(_ a: Session, _ b: Session) -> Bool {
        (a.date, a.createdAt, a.id.uuidString) < (b.date, b.createdAt, b.id.uuidString)
    }

    public func needsReviewNote(at now: Date) -> Bool {
        !isCancelled && !skipsReview && date <= now && (reviewNoteId == nil || reviewNoteUnfinished)
    }
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
    /// starting within its time (or a date-only one that day) stands for it even when cancelled, so a 휴강 moves on to the next.
    /// Exam weeks (counted from `start`) hold no lectures. An exam in a class's time is part of that class, so it
    /// doesn't take the class away.
    public static func suggestion(
        schedule: [ClassTime], sessions: [Session], from start: LocalDate?, to end: LocalDate?,
        examWeeks: Set<Int> = [], now: Date, calendar: Calendar
    ) -> Suggestion? {
        planned(
            schedule: schedule, sessions: sessions, from: start, to: end, examWeeks: examWeeks,
            days: 8, now: now, calendar: calendar
        ).first
    }

    /// Every class the schedule still holds, from the one under way to the term's end, that no session stands for,
    /// by the same rules as `suggestion`. Nothing is stored: a class is made a session only when something is done to
    /// it, so a change to the class times or the term moves the plan with it. Without an end, the coming week only;
    /// `days` caps it sooner.
    public static func planned(
        schedule: [ClassTime], sessions: [Session], from start: LocalDate?, to end: LocalDate?,
        examWeeks: Set<Int> = [], days: Int? = nil,
        now: Date, calendar: Calendar
    ) -> [Suggestion] {
        guard !schedule.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        let anchor = start?.date(in: calendar)
        let limit = days ?? (end == nil ? 8 : Int.max)
        let dates = sessions.map(\.date)
        let dateOnly = Set(dates)

        var result: [Suggestion] = []
        var offset = 0
        while offset < limit {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            offset += 1
            let local = LocalDate(day, in: calendar)
            // End first: a term saved with its start after its end would otherwise skip days forever.
            if let end, local > end { break }
            if let start, local < start { continue }
            if let anchor, examWeeks.contains(week(of: day, anchor: anchor, calendar: calendar)) { continue }

            let weekday = calendar.isoWeekday(of: day)
            for slot in schedule.filter({ $0.weekday == weekday }).sorted(by: { $0.startMinute < $1.startMinute }) {
                let begin = calendar.date(byAdding: .minute, value: slot.startMinute, to: day)!
                let finish = calendar.date(byAdding: .minute, value: slot.endMinute, to: day)!
                guard finish > now else { continue }
                // Anywhere in the slot, not only at its start: a class that began late, or one imported from a calendar
                // event that starts off the slot, is still that class. A makeup outside the slot stays its own.
                if !dateOnly.contains(day) && !dates.contains(where: { $0 >= begin && $0 < finish }) {
                    result.append(Suggestion(date: begin, end: finish, room: slot.room, link: slot.link))
                }
            }
        }
        return result
    }

    /// A new session at `date`. Its week counts Monday-based weeks from the term's start (or, without one, from the
    /// earliest session).
    public static func session(
        at date: Date, sessions: [Session], termStart: LocalDate?,
        calendar: Calendar, device: DeviceID, now: Date
    ) -> Session {
        let anchor = termStart?.date(in: calendar) ?? sessions.map(\.date).min() ?? date
        return Session(device: device, at: now, week: week(of: date, anchor: anchor, calendar: calendar), date: date)
    }

    /// Monday-based weeks, the week holding `anchor` being the first.
    public static func week(of date: Date, anchor: Date, calendar: Calendar) -> Int {
        let firstMonday = calendar.startOfWeek(containing: anchor)
        return max(1, calendar.dateComponents([.day], from: firstMonday, to: calendar.startOfDay(for: date)).day! / 7 + 1)
    }
}

extension CourseFile {
    /// Sessions made ahead of time that nothing has touched yet: in the future, a plain lecture, and with no end,
    /// link, note, ink, material, unit, attendance or recording. A kind, end or link is something someone set up on purpose. `notedSessions` are those a note's frontmatter points to.
    public func untouchedFutureSessions(now: Date, notedSessions: Set<UUID>) -> [Session] {
        sessions.filter { s in
            s.date > now && s.kind == .lecture && s.end == nil && s.link == nil && isUnlinked(s, notedSessions: notedSessions)
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
    /// Moves a session to `date`, and into that date's week. Its name follows the new date, but names already written
    /// into notes and recordings stay. An end of its own moves with it.
    public mutating func reschedule(_ id: UUID, to date: Date, termStart: LocalDate?, calendar: Calendar) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].week = week(of: date, moving: id, termStart: termStart, calendar: calendar)
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

extension [ClassTime] {
    /// The course's usual class in minutes: its most common slot length, the longer on a tie, so a makeup for a two-hour
    /// lab runs two hours. Nil without class times.
    public var usualMinutes: Int? {
        let counts = Dictionary(map { $0.endMinute - $0.startMinute }.filter { $0 > 0 }.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }
}

/// A meeting link as pasted from an invite (Zoom, Meet, Teams, ...).
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
            let host = url.host(), host.contains(".")
        else { return nil }
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
        app.queryItems =
            [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: parts[1])]
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
        Dictionary(
            units.compactMap { u in
                guard let n = u.labNumber, let first = sessions.filter({ u.sessionIds.contains($0.id) }).min(by: { $0.date < $1.date })
                else { return nil }
                return (n, first.week)
            }, uniquingKeysWith: { a, _ in a })
    }

    /// Links the session to experiment `number`'s unit, making `Lab<NN> <experiment>` at the top level when there is
    /// none, so the parts of a two-session experiment share one unit. `id` is the new unit's.
    public mutating func linkLab(_ number: Int, session: UUID, experiment: String, id: UUID = UUID(), device: DeviceID, at now: Date) {
        let unit =
            units.first { $0.labNumber == number }?.id
            ?? {
                let title = [AssignmentKind.lab.folderName(number), experiment].filter { !$0.isEmpty }.joined(separator: " ")
                units.append(Unit(id: id, device: device, at: now, title: title, order: UnitTree.nextOrder(under: nil, in: units)))
                return id
            }()
        if !units.contains(where: { $0.id == unit && $0.sessionIds.contains(session) }) { toggle(session: session, unit: unit) }
    }
}

/// `file` is the audio's course-relative path now; `name` has no extension.
public struct RecordingRetitle: Equatable, Sendable {
    public var recording: UUID
    public var file: String
    public var name: String

    public init(recording: UUID, file: String, name: String) {
        self.recording = recording
        self.file = file
        self.name = name
    }
}

/// `path` is course-relative.
public struct NoteRetitle: Equatable, Sendable {
    public var note: UUID
    public var path: String
    public var title: String

    public init(note: UUID, path: String, title: String) {
        self.note = note
        self.path = path
        self.title = title
    }
}

extension CourseFile {
    /// Nothing was taught at a cancelled class, so a link list leaves it out; one linked already stays so it can be unlinked.
    public func linkableSessions(keeping linked: (Session) -> Bool) -> [Session] {
        sessions.filter { !$0.isCancelled || linked($0) }.sorted(by: Session.inOrder)
    }

    /// What the class covered: the deepest units linked to it, less `besides` (the unit whose page lists the class
    /// says it already). Nil without one.
    public func subject(of session: Session, besides: UUID? = nil) -> String? {
        let units = UnitTree.deepest(units(of: session), in: units).filter { $0.id != besides }
        return units.isEmpty ? nil : units.map(\.title).joined(separator: " · ")
    }

    /// `11/3(화)`, where what the class covered is already said around it (a unit's own classes, say).
    public func day(of session: Session, calendar: Calendar) -> String { Self.day(session.date, calendar: calendar) }

    /// `11/3(화)`: the one short day the app writes, a class's or a deadline's.
    public static func day(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return String(localized: .sessionDay(c.month!, c.day!, ClassTime.weekdayNames[calendar.isoWeekday(of: date) - 1]))
    }

    /// `11/13(금) 23:59`, or `11/13(금) 오후 11:59` under a 12-hour setting: the minute follows the system's clock
    /// setting as every other time in the app does, so a deadline never reads in a different clock than the times
    /// beside it.
    public static func deadline(_ date: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return day(date, calendar: calendar) + " " + date.formatted(time)
    }

    /// `11/3(화): 행복과 습관`, or the day alone when nothing says what the class covered: the one name a
    /// class is shown by. Classes are no longer called `10주차-2`, which moved whenever a makeup came before them.
    public func title(of session: Session, calendar: Calendar) -> String {
        let day = day(of: session, calendar: calendar)
        return subject(of: session).map { String(localized: .sessionTitled(day, $0)) } ?? day
    }

    /// `11-03`: how the command line points at a class and prints it, the day its note's file name starts with. A day
    /// with another class adds the start, `11-03 14:00`, even when both start then (date-only imports): the bare day
    /// names every class that day, so it can't be one class's own. Those at the same minute count on with ` 2` as
    /// taken file names do; a month and day the course also met in another year takes the year. So every class of a
    /// course has its own, and it changes only when a class is added on its own day. The calendar day, not the study
    /// day: the note of a class at 1:00 is named for that date too.
    public func reference(of session: Session, calendar: Calendar) -> String {
        let all = sessions.contains { $0.id == session.id } ? sessions : sessions + [session]
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: session.date)
        let sameMonthDay = all.filter {
            let d = calendar.dateComponents([.month, .day], from: $0.date)
            return d.month == c.month && d.day == c.day
        }
        let otherYear = sameMonthDay.contains { calendar.component(.year, from: $0.date) != c.year }
        var ref = (otherYear ? String(format: "%04d-", c.year!) : "") + String(format: "%02d-%02d", c.month!, c.day!)

        let sameDay = sameMonthDay.filter { calendar.isDate($0.date, inSameDayAs: session.date) }
        guard sameDay.count > 1 else { return ref }
        ref += String(format: " %02d:%02d", c.hour!, c.minute!)

        let minute = { (s: Session) in calendar.dateComponents([.hour, .minute], from: s.date) }
        let sameMinute = sameDay.filter { minute($0) == minute(session) }.sorted(by: Session.inOrder)
        if let i = sameMinute.firstIndex(where: { $0.id == session.id }), i > 0 { ref += " \(i + 1)" }
        return ref
    }

    /// What may be typed for a class: its reference, its day as `11/3`, `11-03` or `2026-11-03`, and what it covered.
    /// A day with two classes is typed for both, so a lookup by it lists their references instead of guessing.
    public func references(of session: Session, calendar: Calendar) -> [String] {
        let d = calendar.dateComponents([.year, .month, .day], from: session.date)
        return [
            reference(of: session, calendar: calendar), "\(d.month!)/\(d.day!)", String(format: "%02d-%02d", d.month!, d.day!),
            String(format: "%04d-%02d-%02d", d.year!, d.month!, d.day!),
        ] + (subject(of: session).map { [$0] } ?? [])
    }

    /// The classes `text` names by `references`, ignoring case and spaces: one for its reference, every class of a day.
    public func sessions(matching text: String, calendar: Calendar) -> [Session] {
        let key = Self.referenceKey(text)
        guard !key.isEmpty else { return [] }
        return sessions.filter { s in references(of: s, calendar: calendar).contains { Self.referenceKey($0) == key } }.sorted(
            by: Session.inOrder)
    }

    static func referenceKey(_ text: String) -> String { text.lowercased().filter { !$0.isWhitespace } }

    /// `11-03(화)`: a recording's file name, the day its notes start with. A second recording that day gets ` 2`.
    public func recordingName(of session: Session, calendar: Calendar) -> String { fileDay(of: session, calendar: calendar) }

    /// `11-05(목) Principles of reliable data transfer`, the day and the class's units, with ` 정리` for a review note.
    /// The title becomes the file name, so `session note` and the new-note sheet must name a session's note the same
    /// way. `-` stands for the title's `/`, which a file name can't hold. A note keeps the name it was made with when the
    /// class's units change, as do those named by the topic classes once had.
    public func noteTitle(for session: Session, kind: NoteKind, calendar: Calendar) -> String {
        let day = fileDay(of: session, calendar: calendar)
        let subject = subject(of: session).map(Self.noteSubject).flatMap { $0.isEmpty ? nil : $0 }
        let title = subject.map { "\(day) \($0)" } ?? day
        return kind == .review ? "\(title) 정리" : title
    }

    /// Session notes still named `10주차-2` or `10주차-2 정리`, as notes were named before #273, with the title a note
    /// gets now. A review note covering several classes takes its first. A note the user titled, or one no session
    /// points at, keeps its name.
    public func legacySessionNoteRetitles(calendar: Calendar) -> [NoteRetitle] {
        notes.compactMap { entry in
            guard entry.kind == .rough || entry.kind == .review,
                let session = sessions(pointingAt: entry.id).first(where: { $0.note(of: entry.kind) == entry.id })
            else { return nil }
            let name = ((entry.path as NSString).lastPathComponent as NSString).deletingPathExtension
            guard name.precomposedStringWithCanonicalMapping.wholeMatch(of: /\d+주차-\d+( 정리)?( \d+)?/) != nil else { return nil }
            return NoteRetitle(note: entry.id, path: entry.path, title: noteTitle(for: session, kind: entry.kind, calendar: calendar))
        }
    }

    /// Recordings named by the old rule, `3주차-1.m4a` (or `3주차-1 2.m4a`), with the name a recording of their class
    /// gets now. A recording of no class keeps its name, as does one the user named.
    public func legacyRecordingRetitles(calendar: Calendar) -> [RecordingRetitle] {
        recordings.compactMap { r in
            guard let session = r.sessionId.flatMap({ id in sessions.first { $0.id == id } }) else { return nil }
            let name = ((r.file as NSString).lastPathComponent as NSString).deletingPathExtension
            guard name.precomposedStringWithCanonicalMapping.wholeMatch(of: /\d+주차-\d+( \d+)?/) != nil else { return nil }
            return RecordingRetitle(recording: r.id, file: r.file, name: recordingName(of: session, calendar: calendar))
        }
    }

    func fileDay(of session: Session, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: session.date)
        return String(format: "%02d-%02d", c.month!, c.day!) + "(\(Self.noteWeekdays[calendar.isoWeekday(of: session.date) - 1]))"
    }

    /// In code, not the catalog: a file name must not change with the device's language.
    static let noteWeekdays = ["월", "화", "수", "목", "금", "토", "일"]

    static let noteSubjectLimit = 60

    /// The subject as it can sit in a file name: path and Obsidian link characters dropped or made `-` (the store
    /// would otherwise turn `TCP: flow` into `TCP- flow`), and short enough that Finder doesn't truncate the name.
    /// Units joined by ` · ` are kept whole, as many as fit; one cut at a word loses the `and`, `of` or `(` left
    /// hanging, which read as a broken name.
    static func noteSubject(_ subject: String) -> String {
        let parts = subject.components(separatedBy: " · ").map(fileNameSafe).filter { !$0.isEmpty }
        var kept: [String] = []
        for part in parts {
            guard (kept + [part]).joined(separator: " · ").count <= noteSubjectLimit else { break }
            kept.append(part)
        }
        if kept.isEmpty, let first = parts.first { kept = [shortened(first)] }
        return kept.joined(separator: " · ")
    }

    static func fileNameSafe(_ text: String) -> String {
        let s = String(
            text.map { ch -> Character in
                if "/\\|".contains(ch) { return "-" }
                if ":#^[]".contains(ch) || ch.isNewline { return " " }
                return ch
            })
        return String(s.split(whereSeparator: \.isWhitespace).joined(separator: " ").drop { $0 == "." })
    }

    static let danglingWords: Set<String> = [
        "a", "an", "and", "as", "at", "by", "for", "from", "in", "into", "of", "on", "or", "the", "to", "under", "vs", "with", "&",
    ]

    static func shortened(_ text: String) -> String {
        var words: [Substring] = []
        for word in text.split(separator: " ") {
            guard (words + [word]).joined(separator: " ").count <= noteSubjectLimit else { break }
            words.append(word)
        }
        guard !words.isEmpty else { return String(text.prefix(noteSubjectLimit)) }

        var s = words.joined(separator: " ")
        while true {
            let before = s
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,;-·."))
            if let last = s.split(separator: " ").last, danglingWords.contains(last.lowercased()) { s = String(s.dropLast(last.count)) }
            if s.filter({ $0 == "(" }).count > s.filter({ $0 == ")" }).count, let open = s.lastIndex(of: "(") { s = String(s[..<open]) }
            if s == before { break }
        }
        return s.isEmpty ? String(text.prefix(noteSubjectLimit)) : s
    }

    /// A past class still owing its review note: not when the session or the whole course is left out of review.
    public func needsReviewNote(_ session: Session, at now: Date) -> Bool {
        course.reviews != false && session.needsReviewNote(at: now)
    }

    /// A class held and reviewed that no unit covers: its review never reaches the unit queue until one is linked.
    public func needsUnits(_ session: Session, at now: Date) -> Bool {
        course.reviews != false && !session.isCancelled && !session.skipsReview && session.date <= now
            && !units.contains { $0.sessionIds.contains(session.id) }
    }

    public func units(of session: Session) -> [Unit] {
        UnitTree.outline(units).map(\.unit).filter { $0.sessionIds.contains(session.id) }
    }
}

extension CourseFile {
    /// Drops every session's link to a deleted note, so no session claims a rough or review note that is gone.
    public mutating func forgetNote(_ id: UUID) {
        for i in sessions.indices { unlinkNote(id, from: sessions[i].id) }
    }

    /// Takes the note off one session, leaving any other session it covers.
    public mutating func unlinkNote(_ id: UUID, from session: UUID) {
        guard let i = sessions.firstIndex(where: { $0.id == session }) else { return }
        if sessions[i].roughNoteId == id { sessions[i].roughNoteId = nil }
        if sessions[i].reviewNoteId == id {
            sessions[i].reviewNoteUnfinished = false
            sessions[i].reviewNoteId = nil
        }
    }

    /// Makes the note `session`'s rough or review note, in place of the one it had. A rough note leaves any session it
    /// was linked to before; a review note may cover several classes caught up on at once, so it is added and keeps
    /// the others. A note that was another kind leaves every session. Other kinds aren't a session's note, so they
    /// only unlink, as does no session.
    public mutating func linkNote(_ id: UUID, to session: UUID?, as kind: NoteKind) {
        let keeps = kind == .review && session != nil
        for s in sessions where s.roughNoteId == id || (!keeps && s.reviewNoteId == id) { unlinkNote(id, from: s.id) }

        guard let session, let i = sessions.firstIndex(where: { $0.id == session }) else { return }
        switch kind {
        case .rough: sessions[i].roughNoteId = id
        case .review:
            // The unfinished mark belongs to the note but is kept on its sessions: a session joining a note being
            // written takes the mark, and one linked again keeps its own (changing only the math syntax is not
            // writing it).
            let unfinished = sessions[i].reviewNoteId == id ? sessions[i].reviewNoteUnfinished : isReviewNoteUnfinished(id)
            sessions[i].reviewNoteId = id
            sessions[i].reviewNoteUnfinished = unfinished
        default: break
        }
    }

    /// Whether the review note is still being written, as marked on any session it covers.
    public func isReviewNoteUnfinished(_ id: UUID) -> Bool {
        sessions.contains { $0.reviewNoteId == id && $0.reviewNoteUnfinished }
    }

    /// Marks the review note written or not on every session it covers, so the classes reviewed together finish together.
    public mutating func setReviewNoteUnfinished(_ id: UUID, _ unfinished: Bool) {
        for i in sessions.indices where sessions[i].reviewNoteId == id { sessions[i].reviewNoteUnfinished = unfinished }
    }
}

extension Session {
    /// The session's rough or review note. A session holds one of each, so another note of that kind can't take it.
    public func note(of kind: NoteKind) -> UUID? {
        switch kind {
        case .rough: roughNoteId
        case .review: reviewNoteId
        default: nil
        }
    }
}
