import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct TodayCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "today", abstract: "오늘 화면과 같은 요약: 시험, 수업, 복습, 마감, 시험 계획", discussion: """
        이번 학기 과목만 본다. 오늘의 범위는 설정의 하루 경계를 따른다.

        예시:
          folio today
          folio today --json
        """)
    @OptionGroup var g: GlobalOptions

    struct Summary: Encodable {
        struct Item: Encodable {
            var course: String
            var courseId: UUID
            var id: UUID
            var title: String
            var at: Date?
            var detail: String?
        }

        var studyDay: String
        var ongoing: Item?
        var exams: [Item]
        var classes: [Item]
        var reviewNotes: [Item]
        var reviews: [Item]
        var deferredReviews: [Item]
        var deadlines: [Item]
        var plan: [Item]
        var attendance: [Item]
        /// Seconds per course over the last 14 study days.
        var studyTime: [Item]
    }

    func run() throws {
        let r = Resolver(try CLI.context(g))
        let ctx = r.ctx
        let settings = try ctx.settings()
        let semester = try r.currentSemester()
        let courses = r.courses.filter { $0.course.semesterId == semester.id && $0.file != nil }
        let files = courses.compactMap(\.file)
        let logs = Dictionary(courses.map { c in (c.id, (try? c.store?.log.readAll()) ?? []) }) { a, _ in a }
        let code = Dictionary(courses.map { ($0.id, $0.code) }) { a, _ in a }
        let tag = Dictionary(courses.map { ($0.id, $0.tag) }) { a, _ in a }
        let file = Dictionary(courses.map { ($0.id, $0.file!) }) { a, _ in a }
        let now = ctx.now, calendar = ctx.calendar

        let summary = TodaySummary.build(courses: files, now: now, settings: settings, calendar: calendar)
        let queue = ReviewScheduler.queue(courses: courses.map { ($0.file!, logs[$0.id]!.events(ReviewEvent.self)) },
                                          settings: settings, calendar: calendar, now: now)
        let done = ExamPlan.done(logs.values.flatMap { $0 }.events(PlanCheckEvent.self))
        let first = summary.studyDay.adding(days: -13)
        func item(_ course: UUID, _ id: UUID, _ title: String, at: Date? = nil, _ detail: String? = nil) -> Summary.Item {
            Summary.Item(course: code[course] ?? "", courseId: course, id: id, title: title, at: at, detail: detail)
        }
        func session(_ s: TodaySummary.SessionItem) -> Summary.Item {
            item(s.courseId, s.session.id, file[s.courseId]?.name(of: s.session) ?? "", at: s.session.date, s.session.topic.isEmpty ? nil : s.session.topic)
        }
        let review = { (e: ReviewEntry) in item(e.courseId, e.item.unitId, e.unitTitle, e.item.overdueDays > 0 ? "\(e.item.overdueDays)일 밀림" : nil) }
        let out = Summary(
            studyDay: summary.studyDay.description,
            ongoing: TodaySummary.ongoingClass(in: files, at: now, calendar: calendar).map {
                item($0.courseId, $0.session.id, file[$0.courseId]?.name(of: $0.session) ?? "", at: $0.end, "\(Int(($0.end.timeIntervalSince(now) / 60).rounded(.up)))분 남음")
            },
            exams: summary.exams.map { item($0.courseId, $0.exam.id, $0.exam.title, at: $0.exam.start, $0.dDay == 0 ? "D-day" : "D-\($0.dDay)") },
            classes: summary.classesToday.map(session),
            reviewNotes: summary.missingReviewNotes.map(session),
            reviews: queue.filter { $0.item.deferred == nil }.map(review),
            deferredReviews: queue.filter { $0.item.deferred != nil }.map(review),
            deadlines: summary.deadlines.map { item($0.courseId, $0.assignment.id, $0.assignment.title, at: $0.assignment.due) },
            plan: ExamPlan.items(on: summary.studyDay, courses: files).map { item($0.courseId, $0.item.id, $0.item.title, $0.exam.title + (done.contains($0.item.id) ? " · 완료" : "")) },
            attendance: courses.compactMap { c in
                c.file!.capOneAway(at: now).map { w in
                    item(c.id, c.id, c.course.title, "결석 \(w.absences)회 · 한 번 더 결석하면 최대 \((try? ctx.catalog())?.grade(w.cap.maxGrade)?.symbol ?? "상한")")
                }
            },
            studyTime: courses.compactMap { c in
                let seconds = StudyTime.perDay(logs[c.id]!.events(StudySessionEvent.self).map(\.event), settings: settings, calendar: calendar)
                    .filter { $0.key >= first }.values.reduce(0, +)
                return seconds > 0 ? item(c.id, c.id, c.course.title, StudyTime.label(seconds)) : nil
            }
        )
        if g.json { return try printJSON(out) }

        say((summary.studyDay.date(in: calendar) ?? now).formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "ko_KR"))).styled(.bold)
            + "  " + (semester.folder?.name ?? "").styled(.dim))
        func section(_ title: String, _ items: [Summary.Item], time: Bool = true) {
            guard !items.isEmpty else { return }
            say("")
            say(title.styled(.bold, .cyan))
            let t = Table(header: ["", "", "", ""], rows: items.map { i in
                let at = i.at.map { time ? when($0, now: now, time: true) : "" } ?? ""
                // A near exam's date already reads "D-7"; the detail would say it twice.
                let detail = i.detail.map { at.plain.hasPrefix($0) ? "" : $0 } ?? ""
                return [tag[i.courseId] ?? i.course, i.title, at, detail.styled(.dim)]
            }, shrink: [1, 3])
            // Each section's title says what the columns are; a header row per section would only repeat it.
            t.render().dropFirst().forEach { say($0) }
        }
        if let o = out.ongoing { section("진행 중 수업", [o]) }
        section("시험", out.exams)
        section("오늘 수업", out.classes)
        section("복습 노트 쓰기", out.reviewNotes)
        section("오늘 복습", out.reviews, time: false)
        section("하루 상한을 넘어 내일로 미룸", out.deferredReviews, time: false)
        section("마감", out.deadlines)
        section("시험 계획", out.plan, time: false)
        section("결석 주의", out.attendance, time: false)
        section("최근 2주 공부 시간", out.studyTime, time: false)
    }
}
