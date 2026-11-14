import Foundation

extension MaterialIntake {
    public static func guess(
        _ file: IncomingFile, places: [String], sessions: [Session], exams: [Exam] = [], now: Date, settings: Settings,
        calendar: Calendar
    ) -> IntakeGuess {
        let name = file.name.precomposedStringWithCanonicalMapping
        let lower = name.lowercased()
        let kinds = settings.assignmentKindTable
        let offered = { (folder: CourseFolder) in places.contains(folder.rawValue) ? folder.rawValue : nil }
        let lecture = { (why: IntakeGuess.Why?, week: Int?) in
            var guess = IntakeGuess(folder: CourseFolder.lectures.rawValue, why: why)
            (guess.session, guess.sessionWhy) = session(week: week, among: sessions, now: now, settings: settings, calendar: calendar)
            return guess
        }

        for rule in FileRule.rules(for: .intake) {
            guard let m = rule.match(name, kinds: kinds) else { continue }
            let folder: String?
            switch rule.kind {
            case .lectureFile, .labManual, .week: return lecture(.named(m.words), m.number)
            case .assignment: folder = m.assignment.flatMap { assignmentFolder($0, number: m.number, places: places, kinds: kinds) }
            case .pastExam: folder = offered(.inherited)
            case .syllabus: folder = offered(.syllabus)
            case .examFile: folder = examFolder(for: lower, places: places, exams: exams, now: now)
            case .textbook: folder = offered(.textbooks)
            case .exercise: folder = offered(.exercises)
            case .selfMade, .numbered, .notes: folder = nil
            }
            if let folder { return IntakeGuess(folder: folder, why: .named(m.words)) }
        }
        if let pages = file.pages, pages >= 150, let folder = offered(.textbooks) {
            return IntakeGuess(folder: folder, why: .book(pages: pages))
        }
        if file.landscape, let pages = file.pages {
            return lecture(.slides(pages: pages), nil)
        }
        return lecture(nil, nil)
    }

    // 같은 번호의 과제 폴더 중 종류가 맞는 것을 고르고, 번호가 맞는 폴더가 하나뿐이면 종류가 달라도 그 폴더다.
    static func assignmentFolder(_ kind: AssignmentKind, number: Int?, places: [String], kinds: [AssignmentKind]) -> String? {
        let base = CourseFolder.assignments.rawValue + "/"
        let parsed = places.filter { $0.hasPrefix(base) }.compactMap { place in
            StandardLayout.assignmentFolder(String(place.dropFirst(base.count)), kinds: kinds).map { (place, $0) }
        }
        let numbered = parsed.filter { $0.1.number == number }
        return numbered.first { $0.1.prefix == kind.prefix }?.0 ?? (numbered.count == 1 ? numbered.first?.0 : nil)
    }

    static func examFolder(for lower: String, places: [String], exams: [Exam], now: Date) -> String? {
        let offered = exams.compactMap { e in folder(of: e).flatMap { places.contains($0) ? (exam: e, folder: $0) : nil } }
        let said = { (word: Regex<Substring>) in
            lower.contains(word)
                ? offered.first { $0.folder.lowercased().contains(word) || $0.exam.title.lowercased().contains(word) }?.folder : nil
        }
        if let folder = said(Keywords.midterm) ?? said(Keywords.final) { return folder }
        let dated = offered.compactMap { o in o.exam.start.map { (start: $0, folder: o.folder) } }.sorted { $0.start < $1.start }
        return (dated.first { $0.start >= now } ?? dated.last)?.folder
    }

    static func session(
        week: Int?, among sessions: [Session], now: Date, settings: Settings,
        calendar: Calendar
    ) -> (UUID?, IntakeGuess.SessionWhy?) {
        let today = settings.studyDay(of: now, calendar: calendar)
        let isToday = { (s: Session) in settings.studyDay(of: s.date, calendar: calendar) == today }
        let held = sessions.filter { !$0.isCancelled }.sorted(by: Session.inOrder)
        let latest = { (among: [Session]) in Session.latest(among: among, now: now, settings: settings, calendar: calendar) }

        if let week {
            // 수업이 없는 주(오래된 슬라이드, 아직 만들지 않은 주)에는 회차를 정하지 않는다. 오늘 수업을 고르면 이름이 다른
            // 주를 말하는데도 오늘 수업의 주차가 이름 앞에 붙기 때문이다.
            let ofWeek = held.filter { $0.week == week }
            return (latest(ofWeek) ?? ofWeek.first).map { ($0.id, .week(week)) } ?? (nil, nil)
        }
        guard let s = latest(held) else { return (nil, nil) }
        return (s.id, isToday(s) ? .today : .latest)
    }
}

extension Session {
    public static func latest(among sessions: [Session], now: Date, settings: Settings, calendar: Calendar) -> Session? {
        held(among: sessions, now: now, settings: settings, calendar: calendar).last
    }

    public static func held(among sessions: [Session], now: Date, settings: Settings, calendar: Calendar) -> [Session] {
        let today = settings.studyDay(of: now, calendar: calendar)
        return sessions.sorted(by: inOrder).filter { $0.date <= now || settings.studyDay(of: $0.date, calendar: calendar) == today }
    }
}
