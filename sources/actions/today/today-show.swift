import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Query(
    "today", "오늘 화면과 같은 요약: 시험, 수업, 복습, 마감, 시험 계획",
    discussion: "이번 학기 과목만 본다. 오늘의 범위는 설정의 하루 경계를 따른다.", examples: ["folio today", "folio today --json"],
    phrases: ["오늘 할 일", "오늘 일정", "지금 뭐 해야", "하루 요약"], panel: true)
public struct TodayShow {
    public struct Item: Encodable {
        public var course: String
        public var courseId: UUID
        public var id: UUID
        public var title: String
        public var at: Date?
        public var detail: String?
    }

    public struct Summary: Encodable {
        public var studyDay: String
        public var ongoing: Item?
        public var exams: [Item]
        public var classes: [Item]
        public var reviewNotes: [Item]
        public var reviews: [Item]
        public var deferredReviews: [Item]
        public var deadlines: [Item]
        public var plan: [Item]
        public var attendance: [Item]
        public var studyTime: [Item]
        // 사람용 출력의 머리에만 쓴다.
        public var day: LocalDate
        public var semester: Semester
    }

    public func read(_ ctx: ReadContext) throws -> Summary {
        let settings = try ctx.settings()
        let semester = try ctx.currentSemester()
        let courses = ctx.courses().filter { $0.file.course.semesterId == semester.id }
        let files = courses.map(\.file)
        let logs = Dictionary(courses.map { c in (c.id, (try? c.store.log.readAll()) ?? []) }) { a, _ in a }
        let code = Dictionary(courses.map { ($0.id, $0.code) }) { a, _ in a }
        let file = Dictionary(courses.map { ($0.id, $0.file) }) { a, _ in a }
        let now = ctx.now, calendar = ctx.calendar

        let summary = TodaySummary.build(courses: files, now: now, settings: settings, calendar: calendar)
        let queue = ReviewScheduler.queue(
            courses: courses.map { ($0.file, (logs[$0.id] ?? []).events(ReviewEvent.self)) },
            settings: settings, calendar: calendar, now: now)
        let done = ExamPlan.done(logs.values.flatMap { $0 }.events(PlanCheckEvent.self))
        let first = summary.studyDay.adding(days: -13)
        func item(_ course: UUID, _ id: UUID, _ title: String, at: Date? = nil, _ detail: String? = nil) -> Item {
            Item(course: code[course] ?? "", courseId: course, id: id, title: title, at: at, detail: detail)
        }
        func session(_ s: TodaySummary.SessionItem) -> Item {
            item(
                s.courseId, s.session.id, file[s.courseId]?.reference(of: s.session, calendar: calendar) ?? "", at: s.session.date,
                file[s.courseId]?.subject(of: s.session))
        }
        let review = { (e: ReviewEntry) in
            item(
                e.courseId, e.item.unitId, e.unitTitle, e.item.overdueDays > 0 ? String(localized: .todayOverdue(e.item.overdueDays)) : nil)
        }
        return Summary(
            studyDay: summary.studyDay.description,
            ongoing: TodaySummary.ongoingClass(in: files, at: now, calendar: calendar).map {
                item(
                    $0.courseId, $0.session.id, file[$0.courseId]?.reference(of: $0.session, calendar: calendar) ?? "", at: $0.end,
                    String(localized: .todayMinutesLeft(Int(($0.end.timeIntervalSince(now) / 60).rounded(.up)))))
            },
            exams: summary.exams.map {
                item($0.courseId, $0.exam.id, $0.exam.title, at: $0.exam.start, DDay.text($0.dDay))
            },
            classes: summary.classesToday.map(session),
            reviewNotes: summary.missingReviewNotes.map(session),
            reviews: queue.filter { $0.item.deferred == nil }.map(review),
            deferredReviews: queue.filter { $0.item.deferred != nil }.map(review),
            deadlines: summary.deadlines.map { item($0.courseId, $0.assignment.id, $0.assignment.title, at: $0.assignment.due) },
            plan: ExamPlan.items(on: summary.studyDay, courses: files).map {
                item(
                    $0.courseId, $0.item.id, $0.item.title,
                    $0.exam.title + (done.contains($0.item.id) ? String(localized: .todayPlanDone) : ""))
            },
            attendance: courses.compactMap { c in
                c.file.capOneAway(at: now).map { w in
                    item(
                        c.id, c.id, c.file.course.title,
                        String(
                            localized: .todayAttendanceWarning(
                                w.absences, (try? ctx.catalog())?.grade(w.cap.maxGrade)?.symbol ?? String(localized: .todayAttendanceCap))))
                }
            },
            studyTime: courses.compactMap { c in
                let seconds = StudyTime.perDay(
                    (logs[c.id] ?? []).events(StudySessionEvent.self).map(\.event), settings: settings, calendar: calendar
                )
                .filter { $0.key >= first }.values.reduce(0, +)
                return seconds > 0 ? item(c.id, c.id, c.file.course.title, StudyTime.label(seconds)) : nil
            },
            day: summary.studyDay, semester: semester
        )
    }
}

extension TodayShow.Summary {
    private enum CodingKeys: String, CodingKey {
        case studyDay, ongoing, exams, classes, reviewNotes, reviews, deferredReviews, deadlines, plan, attendance, studyTime
    }
}
