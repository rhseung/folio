import Foundation

public struct QuickAdd: Equatable, Sendable {
    public var courseId: UUID?
    public var title: String
    // 마감을 늦게 보지 않도록, 마감은 하루 경계를 따르지 않고 실제 시각을 쓴다.
    public var due: Date?
    public var repeats: AssignmentRepeat?
    public var spans: [Span] = []
    var repeatRanges: [Range<String.Index>] = []
    var weekdayRanges: [Range<String.Index>] = []

    public struct Span: Equatable, Sendable {
        public enum Field: Equatable, Sendable {
            case due
            case course(UUID)
            case kind(AssignmentKind, Int)
        }

        public var range: Range<String.Index>
        public var field: Field
    }

    public var dueRanges: [Range<String.Index>] {
        spans.compactMap { s -> Range<String.Index>? in s.field == .due ? s.range : nil }
    }

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

    public static let defaultMinute = 23 * 60 + 59

    public static func parse(
        _ line: String, courses: [Course], codes: [CourseCode] = [], fixedCourse: UUID? = nil, defaultCourse: UUID? = nil,
        now: Date, calendar: Calendar
    ) -> QuickAdd {
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
        joinRules(&words, line: line)
        readNeighbors(&words, today: today)
        joinWeekdays(&words, line: line)
        bindWeekdays(&words)
        detect(&words)
        markEndings(&words)
        return resolve(words, line: line, course: course, courseSpan: courseSpan, now: now, calendar: calendar)
    }
}
