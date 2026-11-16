import Foundation

// 파일 이름 하나로 그 파일이 무엇인지 읽는 규칙이다. 자료 추측(`MaterialIntake.guess`)과 정리 계획(`CoursePlanner`)이 `table`을
// 앞에서부터 읽고 자기가 읽는 규칙(`readers`) 중 처음 맞는 것을 쓴다. 두 곳이 순서를 따로 가지면 같은 낱말이 든 이름이 곳마다
// 다른 규칙에 먼저 걸리므로, 순서는 표 하나에만 둔다.
public struct FileRule: Sendable {
    public enum Kind: Sendable, Equatable {
        case lectureFile, labManual, assignment, pastExam, syllabus, examFile(role: String), selfMade, numbered, textbook, exercise
        case week, notes
    }

    public enum Reader: Sendable {
        case intake, cleanup
    }

    public struct Match: Sendable, Equatable {
        // 이름에서 규칙에 걸린 부분이다. 자료 추측이 왜 그 폴더인지 보일 때 쓴다.
        public var words: String
        public var number: Int?
        public var assignment: AssignmentKind?
    }

    public let kind: Kind
    public let readers: Set<Reader>
    let read: @Sendable (_ name: String, _ kinds: [AssignmentKind]) -> Match?

    init(_ kind: Kind, _ readers: Set<Reader>, read: @escaping @Sendable (_ name: String, _ kinds: [AssignmentKind]) -> Match?) {
        self.kind = kind
        self.readers = readers
        self.read = read
    }

    init(_ kind: Kind, _ readers: Set<Reader>, words: [String]) {
        self.init(kind, readers) { name, _ in
            let lower = name.lowercased()
            return words.first(where: lower.contains).map { Match(words: $0) }
        }
    }

    init(_ kind: Kind, _ readers: Set<Reader>, pattern: String) {
        self.init(kind, readers) { name, _ in
            (try? Regex(pattern)).flatMap { name.firstMatch(of: $0) }.map { Match(words: String(name[$0.range])) }
        }
    }

    public func match(_ name: String, kinds: [AssignmentKind] = AssignmentKind.builtIn) -> Match? {
        read(name, kinds)
    }

    public static func rules(for reader: Reader) -> [FileRule] {
        table.filter { $0.readers.contains(reader) }
    }

    public static func first(for reader: Reader, in name: String, kinds: [AssignmentKind] = AssignmentKind.builtIn) -> (
        kind: Kind, match: Match
    )? {
        rules(for: reader).lazy.compactMap { r in r.match(name, kinds: kinds).map { (r.kind, $0) } }.first
    }
}

extension FileRule {
    // 자료 추측은 `05_`, 교수의 실험 매뉴얼, 과제 번호를 먼저 읽는다. 정리 계획은 과목 폴더 맨 위의 파일만 이 표로 읽고, 폴더 안의
    // 파일은 폴더 이름(`CleanupPlanner.legacyFolder`)으로 정한다.
    public static let table: [FileRule] = [
        FileRule(.lectureFile, [.intake]) { name, _ in
            guard let m = name.firstMatch(of: /^(\d{2})(?:-\d+)?_/), StandardLayout.isLectureFileName(name) else { return nil }
            return Match(words: String(m.0), number: Int(m.1))
        },
        // `Lab 3 manual`도 과제 낱말에 맞으므로 과제 낱말보다 먼저 읽는다. 실험 매뉴얼은 교수가 준 자료라서 렉처 파일이다.
        FileRule(.labManual, [.intake]) { name, _ in
            name.firstMatch(of: /manual|매뉴얼|메뉴얼|실험[\s_-]?안내/.ignoresCase()).map {
                Match(words: String($0.0), number: week(in: name)?.week)
            }
        },
        FileRule(.assignment, [.intake]) { name, kinds in AssignmentKind.mentioned(in: name, kinds: kinds) },
        FileRule(.pastExam, [.intake], pattern: #"(?i)기출|족보|past[\s_-]?exams?|previous[\s_-]?exams?"#),
        FileRule(
            .syllabus, [.intake, .cleanup], words: ["syllabus", "강의계획서", "수업계획서", "orientation", "스케줄", "schedule", "클리닉", "clinic"]),
        FileRule(.syllabus, [.cleanup]) { name, _ in name.lowercased().wholeMatch(of: /ot\..+/).map { _ in Match(words: name) } },
        FileRule(.examFile(role: "Guideline"), [.intake, .cleanup], words: ["guideline", "시험 안내", "시험안내"]),
        FileRule(.examFile(role: "Seating"), [.intake, .cleanup], words: ["seating", "자리", "좌석"]),
        // 교수의 `review.pdf`에도 이런 낱말이 있으므로, 정리 계획은 언제나 제안으로만 쓴다.
        FileRule(.selfMade, [.cleanup]) { name, _ in
            name.lowercased().firstMatch(of: /대비|정리|요약|압축|summary|cheat[\s_-]?sheet|mock|모의/).map { m in Match(words: String(m.output)) }
        },
        FileRule(.numbered, [.cleanup], pattern: #"^\d{1,2}[ _]"#),
        FileRule(.textbook, [.intake, .cleanup], words: ["textbook", "교재", "edition", "solution manual", "introduction to"]),
        // `Diestel (5th).pdf`처럼 괄호로 끝나는 이름은 대개 판이나 저자를 적은 책이다.
        FileRule(.textbook, [.cleanup], pattern: #"\(.+\)\.[^.]+$"#),
        FileRule(.exercise, [.intake], pattern: #"(?i)exercises?|practice|연습"#),
        FileRule(.week, [.intake]) { name, _ in week(in: name).map { Match(words: $0.words, number: $0.week) } },
        FileRule(.notes, [.cleanup]) { name, _ in NoteFormat(path: name) == .markdown ? Match(words: name) : nil },
    ]

    public static let weekWords = ["week", "wk"]
    public static let lectureWords = ["lecture", "lec"]
    public static let chapterWords = ["chapter", "ch"]

    // 낱말 바로 뒤의 한두 자리 번호를 읽는다(`week 3`, `GT_lec3`). 앞에 `\b` 대신 `[^a-z]`를 쓴다. `_`는 낱말 문자인데
    // `GT_lec3` 같은 이름이 흔하기 때문이다. 셋째 자리가 이어지면 번호가 아니다.
    public static func numbered(_ words: [String], in name: String) -> (words: String, number: Int)? {
        guard let regex = try? Regex(#"(?i)(?:^|[^a-z])(("# + alternation(words) + #")[\s_-]*(\d{1,2}))(?!\d)"#),
            let m = name.firstMatch(of: regex), let text = m.output[1].substring, let digits = m.output[3].substring,
            let number = Int(digits)
        else { return nil }
        return (String(text), number)
    }

    public static func koreanWeek(in name: String) -> (words: String, number: Int)? {
        name.firstMatch(of: /(\d{1,2})\s*주차/).flatMap { m in Int(m.1).map { (String(m.0), $0) } }
    }

    public static func week(in name: String) -> (words: String, week: Int)? {
        (numbered(weekWords + lectureWords, in: name) ?? koreanWeek(in: name)).map { ($0.words, $0.number) }
    }

    // 낱말을 정규식의 선택지로 잇는다. 긴 낱말을 앞에 두고, 낱말 안의 띄어쓰기는 `_`나 `-`로 쓰거나 붙여 쓴 이름에도 맞게 한다.
    static func alternation(_ words: [String]) -> String {
        words.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0.lowercased()).replacingOccurrences(of: " ", with: #"[\s_-]?"#) }
            .joined(separator: "|")
    }
}
