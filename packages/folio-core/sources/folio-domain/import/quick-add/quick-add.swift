import Foundation

/// One-line add such as `선대 HW5 금 23:59`. The result is shown before saving.
///
/// Reading goes in three steps, each its own file: `lexicon.swift` reads each word by itself (a weekday, a time, the
/// course, the kind and number), `grammar.swift` joins neighbors (`다음 주` + `금`, `오후` + `3시`, `11월` + `3일`), and
/// `resolve.swift` turns what was read into spans of the line and the values to save. A new kind of word is a
/// recognizer in the lexicon and a field of `Span`.
public struct QuickAdd: Equatable, Sendable {
    public var courseId: UUID?
    public var title: String
    /// Real clock time; deadlines ignore the day boundary so they are never seen late.
    public var due: Date?
    public var repeats: AssignmentRepeat?
    /// Every part of the line that was read, and what it reads as; the title is the words in none of them. The field's
    /// marks and the chips under it read these.
    public var spans: [Span] = []
    /// Where the rule's words (`매주`, `3일마다`) sit, inside the deadline's spans; the repeat chip takes them out of the line.
    var repeatRanges: [Range<String.Index>] = []
    /// Where a rule's weekdays (`월수`) sit; with the rule taken out they become the deadline's own weekday.
    var weekdayRanges: [Range<String.Index>] = []

    public struct Span: Equatable, Sendable {
        public enum Field: Equatable, Sendable {
            /// The deadline's words, the repeat's (`매주`, `월수`) and `까지` among them.
            case due
            /// The course the words name, which a pick on the chip may since have replaced.
            case course(UUID)
            /// The kind and number in the title (`HW5`), which name the assignment's folder. They stay in the title.
            case kind(AssignmentKind, Int)
        }

        public var range: Range<String.Index>
        public var field: Field
    }

    /// Where the words read as the deadline sit in the line.
    public var dueRanges: [Range<String.Index>] {
        spans.compactMap { s -> Range<String.Index>? in s.field == .due ? s.range : nil }
    }

    /// Where the words naming the course sit, when the line names one.
    public var courseRanges: [Range<String.Index>] {
        spans.compactMap { s -> Range<String.Index>? in
            if case .course = s.field { return s.range }
            return nil
        }
    }

    private var kindSpan: (kind: AssignmentKind, number: Int, range: Range<String.Index>)? {
        for s in spans {
            if case let .kind(kind, number) = s.field { return (kind, number, s.range) }
        }
        return nil
    }

    public var kind: AssignmentKind? { kindSpan?.kind }
    public var number: Int? { kindSpan?.number }
    public var kindRange: Range<String.Index>? { kindSpan?.range }
    public var folderName: String? { kindSpan.map { $0.kind.folderName($0.number) } }

    /// Deadline time when only a day is given.
    public static let defaultMinute = 23 * 60 + 59

    /// - Parameter fixedCourse: set when adding from a course's own assignments, so the line need not name the course.
    /// - Parameter defaultCourse: the course the window shows; a course named in the line wins over it.
    public static func parse(_ line: String, courses: [Course], codes: [CourseCode] = [], fixedCourse: UUID? = nil, defaultCourse: UUID? = nil,
                             now: Date, calendar: Calendar) -> QuickAdd {
        var found = line.ranges(of: /\S+/).map { (String(line[$0]), $0) }
        var course = fixedCourse
        var courseSpan: Span?
        if course == nil, let named = readCourse(&found, courses: courses, codes: codes) {
            course = named.id
            courseSpan = Span(range: named.range, field: .course(named.id))
        }
        if course == nil { course = defaultCourse }
        let today = LocalDate(now, in: calendar)
        let year = calendar.component(.year, from: now)
        var words = found.map { Word($0.0, range: $0.1, today: today, year: year) }
        readNeighbors(&words, today: today)
        bindWeekdays(&words)
        detect(&words)
        markEndings(&words)
        return resolve(words, line: line, course: course, courseSpan: courseSpan, now: now, calendar: calendar)
    }
}
