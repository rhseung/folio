import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Query(
    "today", "오늘 화면과 같은 요약: 시험, 수업, 마감, 시험 계획, 남은 오답",
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
        public var wrong: [Item]
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
        let study = Dictionary(
            courses.compactMap { c in
                (try? c.file.units.flatMap { try c.store.loadCards(unit: $0.id).model.cards }).map { cards in
                    (
                        c.id,
                        CourseStudy(
                            file: c.file, cards: cards, log: (logs[c.id] ?? []).studyLog, settings: settings, calendar: calendar, now: now)
                    )
                }
            }
        ) { a, _ in a }
        let first = summary.studyDay.adding(days: -13)
        func item(_ course: UUID, _ id: UUID, _ title: String, at: Date? = nil, _ detail: String? = nil) -> Item {
            Item(course: code[course] ?? "", courseId: course, id: id, title: title, at: at, detail: detail)
        }
        func session(_ s: TodaySummary.SessionItem) -> Item {
            item(
                s.courseId, s.session.id, file[s.courseId]?.reference(of: s.session, calendar: calendar) ?? "", at: s.session.date,
                file[s.courseId]?.subject(of: s.session))
        }
        return Summary(
            studyDay: summary.studyDay.description,
            ongoing: TodaySummary.ongoingClass(in: files, at: now, calendar: calendar).map {
                item(
                    $0.courseId, $0.session.id, file[$0.courseId]?.reference(of: $0.session, calendar: calendar) ?? "", at: $0.end,
                    String(localized: .todayMinutesLeft(Int(($0.end.timeIntervalSince(now) / 60).rounded(.up)))))
            },
            exams: summary.exams.map {
                item($0.courseId, $0.exam.id, $0.exam.title, at: $0.exam.start, DateTimeText.dday(days: $0.dDay))
            },
            classes: summary.classesToday.map(session),
            reviewNotes: summary.missingReviewNotes.map(session),
            wrong: courses.compactMap { c in
                let left = study[c.id]?.allProblems.count { $0.status.needsWork } ?? 0
                return left > 0 ? item(c.id, c.id, c.file.course.title, String(localized: .todayWrongLeft(left))) : nil
            },
            deadlines: summary.deadlines.map { item($0.courseId, $0.assignment.id, $0.assignment.title, at: $0.assignment.due) },
            // 어제 오답 줄은 `wrong`이 과목마다 세므로 여기서는 저장된 항목의 줄만 낸다.
            plan: courses.flatMap { c -> [Item] in
                guard let s = study[c.id] else { return [] }
                return s.planBoard(s.plannedExams(now: now, calendar: calendar)).today.filter { $0.examId != nil }.map { row in
                    let steps = row.steps.map { step in
                        let name = step.stage?.label ?? ""
                        if step.isDone { return String(localized: .todayPlanStepDone(name)).trimmingCharacters(in: .whitespaces) }
                        return step.progress.isStarted ? "\(name) \(step.progress.done)/\(step.progress.total)" : name
                    }
                    let parts = [row.subject ?? ""] + (row.isLate ? [String(localized: .todayPlanLate)] : []) + steps
                    return item(c.id, row.steps.first?.item ?? c.id, row.title, parts.filter { !$0.isEmpty }.joined(separator: " · "))
                }
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
        case studyDay, ongoing, exams, classes, reviewNotes, wrong, deadlines, plan, attendance, studyTime
    }
}
