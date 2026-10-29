import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class SemesterModel {
    let workspace: Workspace
    let semesterID: UUID

    init(workspace: Workspace, semesterID: UUID) {
        self.workspace = workspace
        self.semesterID = semesterID
    }

    struct ExamItem {
        let course: LoadedCourse
        let exam: Exam
        let start: Date
    }

    var semester: Semester? { workspace.transcript.semesters.first { $0.id == semesterID } }

    func courses(in semester: Semester) -> [LoadedCourse] { workspace.courses(in: semester) }

    /// Courses of a semester that live only in transcript.json (no folder).
    func records(in semester: Semester) -> [Course] {
        workspace.transcript.courses.filter { $0.semesterId == semester.id }
    }

    func isCurrent(_ s: Semester) -> Bool { s.isRunning(on: workspace.today) }

    /// The ISO weekday the timetable marks, while the semester is running.
    func markedWeekday(_ s: Semester) -> Int? {
        isCurrent(s) ? workspace.today.date(in: workspace.calendar).map { workspace.calendar.isoWeekday(of: $0) } : nil
    }

    func subtitle(_ s: Semester) -> String {
        guard s.term != .credited else { return String(localized: .semesterCredited) }
        let calendar = workspace.calendar
        guard let start = s.start?.date(in: calendar), let end = s.end?.date(in: calendar) else { return String(localized: .semesterPeriodNone) }
        let format = Date.FormatStyle.dateTime.month().day()
        let range = "\(start.formatted(format)) – \(end.formatted(format))"
        return isCurrent(s) ? String(localized: .semesterPeriodWeek(range, SessionPlanner.week(of: .now, anchor: start, calendar: calendar))) : range
    }

    func stats(_ s: Semester) -> [StatStrip.Item] {
        let courses = courses(in: s), records = records(in: s)
        let summary = GPACalculator.semester(s, courses: workspace.allCourseRecords, catalog: workspace.catalog)
        let credits = (courses.map(\.file.course.credits) + records.map(\.credits)).reduce(0, +)
        return [
            .init(title: String(localized: .semesterStatCourses), value: String(localized: .semesterStatCourseCount(courses.count + records.count))),
            .init(title: String(localized: .semesterCreditsLabel), value: credits.formatted()),
            .init(title: String(localized: .semesterStatGraded), value: String(localized: .semesterCredits(summary.totalCredits.formatted())),
                  detail: String(localized: .semesterStatGradedDetail)),
            .init(title: String(localized: .semesterStatGpa), value: GPACalculator.label(summary.gpa),
                  detail: summary.gpa == nil ? String(localized: .semesterStatGpaOngoing) : String(localized: .semesterStatGpaEffective(summary.effectiveCredits.formatted())),
                  sensitive: true),
        ]
    }

    func detail(_ course: LoadedCourse) -> String {
        ([course.codeLine(workspace)] + course.factChips(workspace)).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func detail(_ record: Course) -> String {
        [String(localized: .semesterCredits(record.credits.formatted())), record.gradingMode.label, String(localized: .semesterCoursesRecordOnly)]
            .joined(separator: " · ")
    }

    /// Every dated exam of the term, soonest first.
    func exams(of courses: [LoadedCourse]) -> [ExamItem] {
        courses.flatMap { c in c.file.exams.compactMap { e in e.start.map { ExamItem(course: c, exam: e, start: $0) } } }.sorted { $0.start < $1.start }
    }

    func examTitle(_ exam: Exam) -> String { exam.title.isEmpty ? exam.kind.label : exam.title }

    func adminFiles(_ s: Semester) -> [URL] { workspace.gist?.adminFiles(of: s) ?? [] }

    func grades(for course: Course) -> [LetterGrade] { workspace.catalog.grades(for: course.gradingMode) }

    func setFinalGrade(_ grade: UUID?, of course: Course) {
        workspace.run(CourseSet(course: course.id, [.finalGrade(grade)]))
    }

    /// Every week of the term labelled with its Monday; past the term's end only as far as a default exam week reaches.
    func weekOptions(_ s: Semester, fallback: Int?) -> [(Int?, String)] {
        let calendar = workspace.calendar
        let anchor = s.start?.date(in: calendar)
        let count = anchor.flatMap { a in s.end?.date(in: calendar).map { SessionPlanner.week(of: $0, anchor: a, calendar: calendar) } } ?? 20
        let weeks = (1...max(count, fallback ?? 1)).map { w -> (Int?, String) in
            let monday = anchor.flatMap { calendar.date(byAdding: .day, value: (w - 1) * 7, to: calendar.startOfWeek(containing: $0)) }
            return (w, monday.map { String(localized: .semesterWeekFrom(w, $0.formatted(.dateTime.month().day()))) } ?? String(localized: .semesterWeek(w)))
        }
        return (fallback == nil ? [(nil, String(localized: .semesterWeekNone))] : []) + weeks
    }

    func setWeek(_ s: Semester, _ key: WritableKeyPath<Semester, Int?>, to week: Int?) {
        workspace.run(key == \Semester.midtermWeek ? SemesterSet(semester: s.id, midtermWeek: .set(week)) : SemesterSet(semester: s.id, finalWeek: .set(week)))
    }

    func date(_ s: Semester, _ key: WritableKeyPath<Semester, LocalDate?>) -> Date {
        s[keyPath: key]?.date(in: workspace.calendar) ?? .now
    }

    func setDate(_ s: Semester, _ key: WritableKeyPath<Semester, LocalDate?>, to date: Date) {
        let day = LocalDate(date, in: workspace.calendar)
        workspace.run(key == \Semester.start ? SemesterSet(semester: s.id, start: .set(day)) : SemesterSet(semester: s.id, end: .set(day)))
    }
}

/// The week as a time grid: which weekdays get a column and which hours the rows span.
struct TimetableLayout {
    let slots: [(course: LoadedCourse, time: ClassTime)]
    /// Monday to Friday, and Saturday and Sunday only when a class falls on them.
    let days: [Int]
    let first: Int
    let last: Int

    init(courses: [LoadedCourse]) {
        slots = courses.flatMap { c in c.file.course.schedule.map { (c, $0) } }
        days = Array(1...max(5, slots.map(\.time.weekday).max() ?? 5))
        first = (slots.map(\.time.startMinute).min() ?? 9 * 60) / 60
        last = ((slots.map(\.time.endMinute).max() ?? 18 * 60) + 59) / 60
    }

    func slots(on day: Int) -> [(course: LoadedCourse, time: ClassTime)] { slots.filter { $0.time.weekday == day } }
}

extension Term {
    var label: String {
        switch self {
        case .spring: String(localized: .semesterTermLabelSpring)
        case .summer: String(localized: .semesterTermLabelSummer)
        case .fall: String(localized: .semesterTermLabelFall)
        case .winter: String(localized: .semesterTermLabelWinter)
        case .credited: String(localized: .semesterTermLabelCredited)
        }
    }
}
