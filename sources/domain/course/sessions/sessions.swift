import Foundation

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
    private var lectures: [UnitPages]?

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
    public var unitIds: [UUID]
    public var roughNoteId: UUID?
    public var reviewNoteId: UUID?
    public var inkIds: [UUID]
    public var materials: [SessionMaterial]
    public var end: Date?
    public var link: String?
    private var noReview: Bool?
    private var reviewNoteDraft: Bool?
    // 휴강인 회차만 `cancelled` 키를, 보강인 회차만 `makeup` 키를 가진다. `kind` 키 하나가 아니라 플래그 둘을 두어야
    // 보강이 생기기 전의 모든 파일이 그대로 읽힌다.
    private var cancelled: Bool?
    private var makeup: Bool?
    private var wrappedUp: Bool?

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

    public var isCancelled: Bool {
        get { kind == .cancelled }
        set { if newValue { kind = .cancelled } else if kind == .cancelled { kind = .lecture } }
    }

    // 출석은 기록이 없는 것으로 저장하므로, 이 값이 없으면 직접 출석한 수업을 끝없이 묻게 된다. 정리에서 비워 둔
    // 칸도 일부러 비운 것으로 본다.
    public var isWrappedUp: Bool {
        get { wrappedUp ?? false }
        set { wrappedUp = newValue ? true : nil }
    }

    public var skipsReview: Bool {
        get { noReview ?? false }
        set { noReview = newValue ? true : nil }
    }

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

    // 같은 시각의 두 수업(날짜만 가져온 회차)은 만든 순서를 지켜서 이름이 뒤바뀌지 않는다.
    public static func inOrder(_ a: Session, _ b: Session) -> Bool {
        (a.date, a.createdAt, a.id.uuidString) < (b.date, b.createdAt, b.id.uuidString)
    }

    public func needsReviewNote(at now: Date) -> Bool {
        !isCancelled && !skipsReview && date <= now && (reviewNoteId == nil || reviewNoteUnfinished)
    }
}

public enum SessionPlanner {
    public struct Suggestion: Sendable, Equatable {
        public var date: Date
        public var end: Date
        public var room: String
        public var link: String?
    }

    public static func suggestion(
        schedule: [ClassTime], sessions: [Session], from start: LocalDate?, to end: LocalDate?,
        examWeeks: Set<Int> = [], now: Date, calendar: Calendar
    ) -> Suggestion? {
        planned(
            schedule: schedule, sessions: sessions, from: start, to: end, examWeeks: examWeeks,
            days: 8, now: now, calendar: calendar
        ).first
    }

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
            // 시작이 끝보다 뒤로 저장된 학기에서 날을 끝없이 건너뛰지 않도록 끝을 먼저 본다.
            if let end, local > end { break }
            if let start, local < start { continue }
            if let anchor, examWeeks.contains(week(of: day, anchor: anchor, calendar: calendar)) { continue }

            let weekday = calendar.isoWeekday(of: day)
            for slot in schedule.filter({ $0.weekday == weekday }).sorted(by: { $0.startMinute < $1.startMinute }) {
                let begin = calendar.date(byAdding: .minute, value: slot.startMinute, to: day)!
                let finish = calendar.date(byAdding: .minute, value: slot.endMinute, to: day)!
                guard finish > now else { continue }
                // 늦게 시작한 수업이나 시간표와 다르게 시작하는 캘린더 일정에서 가져온 수업도 그 수업이므로, 시작 시각만이 아니라
                // 시간 안 어디든 본다. 시간표 밖의 보강은 따로 남는다.
                if !dateOnly.contains(day) && !dates.contains(where: { $0 >= begin && $0 < finish }) {
                    result.append(Suggestion(date: begin, end: finish, room: slot.room, link: slot.link))
                }
            }
        }
        return result
    }

    public static func session(
        at date: Date, sessions: [Session], termStart: LocalDate?,
        calendar: Calendar, device: DeviceID, now: Date
    ) -> Session {
        let anchor = termStart?.date(in: calendar) ?? sessions.map(\.date).min() ?? date
        return Session(device: device, at: now, week: week(of: date, anchor: anchor, calendar: calendar), date: date)
    }

    public static func week(of date: Date, anchor: Date, calendar: Calendar) -> Int {
        let firstMonday = calendar.startOfWeek(containing: anchor)
        return max(1, calendar.dateComponents([.day], from: firstMonday, to: calendar.startOfDay(for: date)).day! / 7 + 1)
    }
}

extension CourseFile {
    public func untouchedFutureSessions(now: Date, notedSessions: Set<UUID>) -> [Session] {
        sessions.filter { s in
            s.date > now && s.kind == .lecture && s.end == nil && s.link == nil && isUnlinked(s, notedSessions: notedSessions)
        }
    }

    public func heldAttendance(at now: Date) -> [Attendance] {
        attendance.filter { a in sessions.first { $0.id == a.sessionId }.map { $0.date <= now && !$0.isCancelled } ?? true }
    }

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

    public func end(schedule: [ClassTime], calendar: Calendar) -> Date? {
        if let end = self.end { return end }
        guard let slot = slot(in: schedule, calendar: calendar) else { return nil }
        return date.addingTimeInterval(TimeInterval((slot.endMinute - slot.startMinute) * 60))
    }

    public func expectedEnd(schedule: [ClassTime], classMinutes: Int, calendar: Calendar) -> Date {
        end(schedule: schedule, calendar: calendar) ?? date.addingTimeInterval(TimeInterval((schedule.usualMinutes ?? classMinutes) * 60))
    }

    public func link(schedule: [ClassTime], calendar: Calendar) -> URL? {
        (self.link ?? slot(in: schedule, calendar: calendar)?.link).flatMap(OnlineLink.url)
    }

    // 시간표 칸이 이미 주는 끝 시각은 저장하지 않는다. 그래야 나중에 수업 시각을 바꾸면 회차의 끝 시각도 따라간다.
    public mutating func setEnd(_ end: Date?, schedule: [ClassTime], calendar: Calendar) {
        self.end = nil
        if let end, end != self.end(schedule: schedule, calendar: calendar) { self.end = end }
    }
}

extension CourseFile {
    public mutating func reschedule(_ id: UUID, to date: Date, termStart: LocalDate?, calendar: Calendar) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].week = week(of: date, moving: id, termStart: termStart, calendar: calendar)
        if let end = sessions[i].end { sessions[i].end = end.addingTimeInterval(date.timeIntervalSince(sessions[i].date)) }
        sessions[i].date = date
    }
}

extension CourseFile {
    public func week(of date: Date, moving id: UUID, termStart: LocalDate?, calendar: Calendar) -> Int {
        let anchor = termStart?.date(in: calendar) ?? (sessions.filter { $0.id != id }.map(\.date) + [date]).min()!
        return SessionPlanner.week(of: date, anchor: anchor, calendar: calendar)
    }
}

extension [ClassTime] {
    public var usualMinutes: Int? {
        let counts = Dictionary(map { $0.endMinute - $0.startMinute }.filter { $0 > 0 }.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }
}

public enum OnlineLink {
    public static func stored(_ text: String?) -> String? {
        text.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func url(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = url.host(), host.contains(".")
        else { return nil }
        return url
    }

    // 웹 링크는 브라우저 탭을 열고 앱으로 넘길지 묻지만, 이 scheme은 바로 앱으로 간다.
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
    public func isoWeekday(of date: Date) -> Int {
        (component(.weekday, from: date) + 5) % 7 + 1
    }

    public func startOfWeek(containing date: Date) -> Date {
        self.date(byAdding: .day, value: -(isoWeekday(of: date) - 1), to: startOfDay(for: date))!
    }
}

extension Unit {
    public var labNumber: Int? {
        title.prefixMatch(of: /(?i)lab\s*(\d{1,3})(?!\d)/).flatMap { Int($0.1) }
    }

    public var labTitle: String {
        guard let m = title.prefixMatch(of: /(?i)lab\s*\d{1,3}[\s:._-]*/) else { return title }
        return String(title[m.range.upperBound...])
    }
}

extension CourseFile {
    public var labNumbers: [String: Int] {
        Dictionary(units.compactMap { u in u.labNumber.map { (u.labTitle, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    public var labWeeks: [Int: Int] {
        Dictionary(
            units.compactMap { u in
                guard let n = u.labNumber, let first = sessions.filter({ u.sessionIds.contains($0.id) }).min(by: { $0.date < $1.date })
                else { return nil }
                return (n, first.week)
            }, uniquingKeysWith: { a, _ in a })
    }

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
    public func linkableSessions(keeping linked: (Session) -> Bool) -> [Session] {
        sessions.filter { !$0.isCancelled || linked($0) }.sorted(by: Session.inOrder)
    }

    public func subject(of session: Session, besides: UUID? = nil) -> String? {
        let units = UnitTree.deepest(units(of: session), in: units).filter { $0.id != besides }
        return units.isEmpty ? nil : units.map(\.title).joined(separator: " · ")
    }

    public func day(of session: Session, calendar: Calendar) -> String { Self.day(session.date, calendar: calendar) }

    public static func day(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return String(localized: .sessionDay(c.month!, c.day!, ClassTime.weekdayNames[calendar.isoWeekday(of: date) - 1]))
    }

    public static func deadline(_ date: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return day(date, calendar: calendar) + " " + date.formatted(time)
    }

    public func title(of session: Session, calendar: Calendar) -> String {
        let day = day(of: session, calendar: calendar)
        return subject(of: session).map { String(localized: .sessionTitled(day, $0)) } ?? day
    }

    // 같은 날 다른 수업이 있으면 시작 시각을 붙인다. 날짜만으로는 그날의 모든 수업을 가리키므로 한 수업의 이름이 될 수
    // 없기 때문이다. 1:00 수업의 노트도 그 날짜로 이름을 지으므로, 공부일이 아니라 달력 날짜를 쓴다.
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

    public func references(of session: Session, calendar: Calendar) -> [String] {
        let d = calendar.dateComponents([.year, .month, .day], from: session.date)
        return [
            reference(of: session, calendar: calendar), "\(d.month!)/\(d.day!)", String(format: "%02d-%02d", d.month!, d.day!),
            String(format: "%04d-%02d-%02d", d.year!, d.month!, d.day!),
        ] + (subject(of: session).map { [$0] } ?? [])
    }

    public func sessions(matching text: String, calendar: Calendar) -> [Session] {
        let key = Self.referenceKey(text)
        guard !key.isEmpty else { return [] }
        return sessions.filter { s in references(of: s, calendar: calendar).contains { Self.referenceKey($0) == key } }.sorted(
            by: Session.inOrder)
    }

    static func referenceKey(_ text: String) -> String { text.lowercased().filter { !$0.isWhitespace } }

    public func recordingName(of session: Session, calendar: Calendar) -> String { fileDay(of: session, calendar: calendar) }

    public func noteTitle(for session: Session, kind: NoteKind, calendar: Calendar) -> String {
        let day = fileDay(of: session, calendar: calendar)
        let subject = subject(of: session).map(Self.noteSubject).flatMap { $0.isEmpty ? nil : $0 }
        let title = subject.map { "\(day) \($0)" } ?? day
        return kind == .review ? "\(title) 정리" : title
    }

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

    static let noteWeekdays = ["월", "화", "수", "목", "금", "토", "일"]

    static let noteSubjectLimit = 60

    // 경로와 Obsidian 링크 문자는 빼거나 `-`로 바꾼다. 그대로 두면 저장소가 `TCP: flow`를 `TCP- flow`로 바꾼다. Finder가
    // 이름을 줄이지 않을 만큼 짧게 자른다. ` · `로 이은 단원은 들어가는 만큼 통째로 둔다. 낱말 단위로 자르면 끝에 남은
    // `and`, `of`, `(` 때문에 이름이 깨진 것처럼 보인다.
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

    public func needsReviewNote(_ session: Session, at now: Date) -> Bool {
        course.reviews != false && session.needsReviewNote(at: now)
    }

    public func needsUnits(_ session: Session, at now: Date) -> Bool {
        course.reviews != false && !session.isCancelled && !session.skipsReview && session.date <= now
            && !units.contains { $0.sessionIds.contains(session.id) }
    }

    public func units(of session: Session) -> [Unit] {
        UnitTree.outline(units).map(\.unit).filter { $0.sessionIds.contains(session.id) }
    }
}

extension CourseFile {
    public mutating func forgetNote(_ id: UUID) {
        for i in sessions.indices { unlinkNote(id, from: sessions[i].id) }
    }

    public mutating func unlinkNote(_ id: UUID, from session: UUID) {
        guard let i = sessions.firstIndex(where: { $0.id == session }) else { return }
        if sessions[i].roughNoteId == id { sessions[i].roughNoteId = nil }
        if sessions[i].reviewNoteId == id {
            sessions[i].reviewNoteUnfinished = false
            sessions[i].reviewNoteId = nil
        }
    }

    public mutating func linkNote(_ id: UUID, to session: UUID?, as kind: NoteKind) {
        let keeps = kind == .review && session != nil
        for s in sessions where s.roughNoteId == id || (!keeps && s.reviewNoteId == id) { unlinkNote(id, from: s.id) }

        guard let session, let i = sessions.firstIndex(where: { $0.id == session }) else { return }
        switch kind {
        case .rough: sessions[i].roughNoteId = id
        case .review:
            // 작성 중 표시는 노트의 것이지만 회차에 둔다. 작성 중인 노트에 합류하는 회차는 그 표시를 받고, 다시 연결한 회차는
            // 자기 표시를 지킨다(수식 문법만 바꾸는 것은 작성이 아니다).
            let unfinished = sessions[i].reviewNoteId == id ? sessions[i].reviewNoteUnfinished : isReviewNoteUnfinished(id)
            sessions[i].reviewNoteId = id
            sessions[i].reviewNoteUnfinished = unfinished
        default: break
        }
    }

    public func isReviewNoteUnfinished(_ id: UUID) -> Bool {
        sessions.contains { $0.reviewNoteId == id && $0.reviewNoteUnfinished }
    }

    public mutating func setReviewNoteUnfinished(_ id: UUID, _ unfinished: Bool) {
        for i in sessions.indices where sessions[i].reviewNoteId == id { sessions[i].reviewNoteUnfinished = unfinished }
    }
}

extension Session {
    public func note(of kind: NoteKind) -> UUID? {
        switch kind {
        case .rough: roughNoteId
        case .review: reviewNoteId
        default: nil
        }
    }
}
