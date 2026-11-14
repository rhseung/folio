import Foundation

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

extension Calendar {
    public func isoWeekday(of date: Date) -> Int {
        (component(.weekday, from: date) + 5) % 7 + 1
    }

    public func startOfWeek(containing date: Date) -> Date {
        self.date(byAdding: .day, value: -(isoWeekday(of: date) - 1), to: startOfDay(for: date))!
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
