import Foundation

extension MaterialIntake {
    public static func guess(
        _ file: IncomingFile, places: [String], sessions: [Session], exams: [Exam] = [], now: Date, settings: Settings,
        calendar: Calendar
    ) -> IntakeGuess {
        let name = file.name.precomposedStringWithCanonicalMapping
        let lower = name.lowercased()
        let offered = { (folder: CourseFolder) in places.contains(folder.rawValue) ? folder.rawValue : nil }
        let lecture = { (why: IntakeGuess.Why?, week: Int?) in
            var guess = IntakeGuess(folder: CourseFolder.lectures.rawValue, why: why)
            (guess.session, guess.sessionWhy) = session(week: week, among: sessions, now: now, settings: settings, calendar: calendar)
            return guess
        }

        if let m = name.firstMatch(of: /^(\d{2})(?:-\d+)?_/), StandardLayout.isLectureFileName(name) {
            return lecture(.named(String(m.0)), Int(m.1))
        }
        // `Lab 3 manual`도 과제 낱말에 맞으므로 과제 낱말보다 먼저 읽는다. 실험 매뉴얼은 교수가 준 자료라서 렉처 파일이다.
        if let m = name.firstMatch(of: /manual|매뉴얼|메뉴얼|실험[\s_-]?안내/.ignoresCase()) {
            return lecture(.named(String(m.0)), week(in: name)?.week)
        }
        if let (folder, words) = assignment(in: name, places: places) {
            return IntakeGuess(folder: folder, why: .named(words))
        }
        if let m = name.firstMatch(of: /기출|족보|past[\s_-]?exams?|previous[\s_-]?exams?/.ignoresCase()), let folder = offered(.inherited) {
            return IntakeGuess(folder: folder, why: .named(String(m.0)))
        }
        if let word = Keywords.syllabus.first(where: lower.contains), let folder = offered(.syllabus) {
            return IntakeGuess(folder: folder, why: .named(word))
        }
        if let word = Keywords.examFiles.flatMap(\.words).first(where: lower.contains),
            let folder = examFolder(for: lower, places: places, exams: exams, now: now)
        {
            return IntakeGuess(folder: folder, why: .named(word))
        }
        if let word = Keywords.textbook.first(where: lower.contains), let folder = offered(.textbooks) {
            return IntakeGuess(folder: folder, why: .named(word))
        }
        if let m = name.firstMatch(of: /exercises?|practice|연습/.ignoresCase()), let folder = offered(.exercises) {
            return IntakeGuess(folder: folder, why: .named(String(m.0)))
        }
        if let (words, week) = week(in: name) {
            return lecture(.named(words), week)
        }
        if let pages = file.pages, pages >= 150, let folder = offered(.textbooks) {
            return IntakeGuess(folder: folder, why: .book(pages: pages))
        }
        if file.landscape, let pages = file.pages {
            return lecture(.slides(pages: pages), nil)
        }
        return lecture(nil, nil)
    }

    // 앞에 `\b` 대신 `[^a-z]`를 쓴다. `_`는 낱말 문자인데 `GT_lec3` 같은 이름이 흔하기 때문이다.
    static func week(in name: String) -> (words: String, week: Int)? {
        if let m = name.firstMatch(of: /(?:^|[^a-z])((?:week|wk|lecture|lec)[\s_-]*(\d{1,2}))(?!\d)/.ignoresCase()) {
            return (String(m.1), Int(m.2)!)
        }
        if let m = name.firstMatch(of: /(\d{1,2})\s*주차/) { return (String(m.0), Int(m.1)!) }
        return nil
    }

    static func assignment(in name: String, places: [String]) -> (folder: String, words: String)? {
        let keyword =
            /(?:^|[^a-z])((hw|homework|assignment|assign|lab|sp|slow[\s_-]?problems?|report|project|reading|과제|숙제)[\s_-]*(\d{1,2}))(?!\d)/
        guard let m = name.firstMatch(of: keyword.ignoresCase()), let number = Int(m.3) else { return nil }
        let prefix: AssignmentKind =
            switch m.2.lowercased() {
            case "lab": .lab
            case "report": .report
            case "project": .project
            case "reading": .reading
            case let word where word == "sp" || word.hasPrefix("slow"): .slowProblem
            default: .homework
            }
        let base = CourseFolder.assignments.rawValue + "/"
        let folders = places.filter { $0.hasPrefix(base) }
        let numbered = folders.filter { StandardLayout.assignmentFolder(String($0.dropFirst(base.count)))?.number == number }
        guard
            let folder = numbered.first(where: {
                StandardLayout.assignmentFolder(String($0.dropFirst(base.count)))?.prefix == prefix.rawValue
            })
                ?? (numbered.count == 1 ? numbered.first : nil)
        else { return nil }
        return (folder, String(m.1))
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
