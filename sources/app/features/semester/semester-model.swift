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

    // MARK: Credited source

    var source = ""

    func loadSource() { source = semester?.source ?? "" }

    private var sourceChange: SemesterSource? {
        let name = source.trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name == semester?.source ? nil : SemesterSource(semester: semesterID, source: name)
    }

    var sourceFolder: String? {
        StandardLayout.creditedFolder(source: source.trimmingCharacters(in: .whitespaces))
    }

    var sourceRefusal: String? { sourceChange.flatMap { workspace.refusal($0) } }

    var canSaveSource: Bool { sourceChange != nil && sourceRefusal == nil }

    func sourceConfirmation() -> String { sourceChange.flatMap { workspace.confirmation($0) } ?? "" }

    func saveSource() {
        guard let sourceChange else { return }
        workspace.run(sourceChange)
        loadSource()
    }

    // MARK: Recording audio

    struct AudioNotice {
        struct Item: Identifiable {
            let course: LoadedCourse
            let count: Int
            let bytes: Int64
            var id: UUID { course.id }
        }
        let items: [Item]
        let kept: Int
        var count: Int { items.map(\.count).reduce(0, +) }
        var bytes: Int64 { items.map(\.bytes).reduce(0, +) }
    }

    private(set) var audio: AudioNotice?

    func refreshAudio() async {
        // `RecordingTrim`처럼 공부일이 아니라 달력 날짜를 쓴다. 공부일을 쓰면 자정 뒤 하루 경계 전에는 액션이 이미
        // 정리를 허락하는데 카드는 숨는다.
        guard let s = semester, s.isOver(on: LocalDate(workspace.now, in: workspace.calendar), among: workspace.transcript.semesters) else {
            audio = nil; return
        }
        let courses = courses(in: s)
        let shelf = courses.map { ($0.store, $0.file.recordings.filter(\.hasAudio)) }

        // 녹음에 줄이 있는지 알려면 받아쓰기 전체를 디코딩해야 하고, 학기에는 75분짜리가 수십 개라서 페이지가 열리며
        // 멈췄다. 그래서 main actor 밖에서 센다.
        let tallies = await Task.detached {
            shelf.map { store, withAudio in
                let trimmable = RecordingRetention.trimmable(withAudio) { store.transcript(of: $0)?.lines.isEmpty == false }
                return (
                    count: trimmable.count, kept: withAudio.count - trimmable.count,
                    bytes: trimmable.map { store.audioSize(of: $0) }.reduce(0, +)
                )
            }
        }.value

        let items = zip(courses, tallies).filter { $1.count > 0 }.map { AudioNotice.Item(course: $0, count: $1.count, bytes: $1.bytes) }
        audio = items.isEmpty ? nil : AudioNotice(items: items, kept: tallies.map(\.kept).reduce(0, +))
    }

    var trimAudio: RecordingTrim { RecordingTrim(semester: semesterID) }

    func trimConfirmation() -> String { workspace.confirmation(trimAudio) ?? "" }

    func trim() async {
        workspace.run(trimAudio)
        await refreshAudio()
    }

    func courses(in semester: Semester) -> [LoadedCourse] { workspace.courses(in: semester) }

    func timetable(_ s: Semester) -> TimetableLayout {
        TimetableLayout(courses: courses(in: s).map(\.file.course))
    }

    func folderCourse(_ course: Course) -> LoadedCourse? { workspace.course(course.id) }

    func isCurrent(_ s: Semester) -> Bool { s.isRunning(on: workspace.today) }

    func markedWeekday(_ s: Semester) -> Int? {
        isCurrent(s) ? workspace.today.date(in: workspace.calendar).map { workspace.calendar.isoWeekday(of: $0) } : nil
    }

    func subtitle(_ s: Semester) -> String {
        guard s.term != .credited else { return String(localized: .semesterCredited) }
        let calendar = workspace.calendar
        guard let start = s.start?.date(in: calendar), let end = s.end?.date(in: calendar) else {
            return String(localized: .semesterPeriodNone)
        }
        let format = Date.FormatStyle.dateTime.month().day()
        let range = "\(start.formatted(format)) – \(end.formatted(format))"
        return isCurrent(s)
            ? String(localized: .semesterPeriodWeek(range, SessionPlanner.week(of: workspace.now, anchor: start, calendar: calendar)))
            : range
    }

    func stats(_ s: Semester) -> [StatStrip.Item] {
        let courses = courses(in: s)
        let summary = GPACalculator.semester(s, courses: workspace.allCourses, catalog: workspace.catalog)
        let credits = courses.map(\.file.course.credits).reduce(0, +)
        return [
            .init(title: String(localized: .semesterStatCourses), value: String(localized: .semesterStatCourseCount(courses.count))),
            .init(title: String(localized: .semesterCreditsLabel), value: credits.formatted()),
            .init(
                title: String(localized: .semesterStatGraded), value: String(localized: .semesterCredits(summary.totalCredits.formatted())),
                detail: String(localized: .semesterStatGradedDetail)),
            .init(
                title: String(localized: .semesterStatGpa), value: GPACalculator.label(summary.gpa),
                detail: summary.gpa == nil
                    ? String(localized: .semesterStatGpaOngoing)
                    : String(localized: .semesterStatGpaEffective(summary.effectiveCredits.formatted())),
                sensitive: true),
        ]
    }

    func detail(_ course: LoadedCourse) -> String {
        ([course.codeLine(workspace)] + course.factChips(workspace)).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func exams(of courses: [LoadedCourse]) -> [ExamItem] {
        courses.flatMap { c in c.file.exams.compactMap { e in e.start.map { ExamItem(course: c, exam: e, start: $0) } } }.sorted {
            $0.start < $1.start
        }
    }

    func examTitle(_ exam: Exam) -> String { exam.title }

    func adminFiles(_ s: Semester) -> [URL] { workspace.gist?.adminFiles(of: s) ?? [] }

    func grades(for course: Course) -> [LetterGrade] { workspace.catalog.grades(for: course.gradingMode) }

    func setFinalGrade(_ grade: UUID?, of course: Course) {
        workspace.run(CourseSet(course: course.id, [.finalGrade(grade)]))
    }

    func weekOptions(_ s: Semester, fallback: Int?) -> [(Int?, String)] {
        let calendar = workspace.calendar
        let anchor = s.start?.date(in: calendar)
        let count =
            anchor.flatMap { a in s.end?.date(in: calendar).map { SessionPlanner.week(of: $0, anchor: a, calendar: calendar) } } ?? 20
        let weeks = (1...max(count, fallback ?? 1)).map { w -> (Int?, String) in
            let monday = anchor.flatMap { calendar.date(byAdding: .day, value: (w - 1) * 7, to: calendar.startOfWeek(containing: $0)) }
            return (
                w,
                monday.map { String(localized: .semesterWeekFrom(w, $0.formatted(.dateTime.month().day()))) }
                    ?? String(localized: .semesterWeek(w))
            )
        }
        return (fallback == nil ? [(nil, String(localized: .semesterWeekNone))] : []) + weeks
    }

    func setWeek(_ s: Semester, _ key: WritableKeyPath<Semester, Int?>, to week: Int?) {
        workspace.run(
            key == \Semester.midtermWeek
                ? SemesterSet(semester: s.id, midtermWeek: .set(week)) : SemesterSet(semester: s.id, finalWeek: .set(week)))
    }

    func date(_ s: Semester, _ key: WritableKeyPath<Semester, LocalDate?>) -> Date {
        s[keyPath: key]?.date(in: workspace.calendar) ?? workspace.now
    }

    func setDate(_ s: Semester, _ key: WritableKeyPath<Semester, LocalDate?>, to date: Date) {
        let day = LocalDate(date, in: workspace.calendar)
        workspace.run(key == \Semester.start ? SemesterSet(semester: s.id, start: .set(day)) : SemesterSet(semester: s.id, end: .set(day)))
    }
}

struct TimetableLayout {
    let slots: [(course: Course, time: ClassTime)]
    let days: [Int]
    let first: Int
    let last: Int

    init(courses: [Course]) {
        slots = courses.flatMap { c in c.schedule.map { (c, $0) } }
        days = Array(1...max(5, slots.map(\.time.weekday).max() ?? 5))
        first = (slots.map(\.time.startMinute).min() ?? 9 * 60) / 60
        last = ((slots.map(\.time.endMinute).max() ?? 18 * 60) + 59) / 60
    }

    func slots(on day: Int) -> [(course: Course, time: ClassTime)] { slots.filter { $0.time.weekday == day } }
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
