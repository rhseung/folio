import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    func reviews(of courseId: UUID) -> [(at: Date, event: ReviewEvent)] {
        (reviewEvents[courseId] ?? []).events(ReviewEvent.self)
    }

    private func reviewInputs(_ course: LoadedCourse, now: Date, extra: [(at: Date, event: ReviewEvent)] = []) -> [UnitReviewInput] {
        UnitReviewInput.all(for: course.file, reviews: reviews(of: course.id) + extra, settings: settings, calendar: calendar, now: now)
    }

    /// Units reviewed today (skips aside, which aren't study) and the days-in-a-row streak, across every course.
    func reviewProgress(now: Date) -> (doneToday: Int, streak: Int) {
        let today = settings.studyDay(of: now, calendar: calendar)
        var done = Set<UUID>()
        var days = Set<LocalDate>()
        for courseId in reviewEvents.keys {
            for r in reviews(of: courseId) where r.event.result != .skip {
                let day = settings.studyDay(of: r.at, calendar: calendar)
                days.insert(day)
                if day == today { done.insert(r.event.unitId) }
            }
        }
        return (done.count, ReviewStreak.days(days, today: today))
    }

    /// Scheduler state per unit. Units without a past session have no cycle yet and are missing from the result.
    func reviewStates(of courseId: UUID, now: Date) -> [UUID: ReviewState] {
        guard let course = course(courseId) else { return [:] }
        let today = settings.studyDay(of: now, calendar: calendar)
        return Dictionary(keepingFirst: reviewInputs(course, now: now).map {
            ($0.unitId, ReviewScheduler.state(of: $0, settings: settings.review, today: today))
        })
    }

    /// The next review day if the unit were finished now with `result`. Runs the real scheduler, so exam limits apply.
    func nextReview(course courseId: UUID, unit: UUID, result: ReviewResult, now: Date) -> LocalDate? {
        guard let course = course(courseId) else { return nil }
        let extra = [(at: now, event: ReviewEvent(unitId: unit, result: result, seconds: 0))]
        let today = settings.studyDay(of: now, calendar: calendar)
        return reviewInputs(course, now: now, extra: extra).first { $0.unitId == unit }
            .flatMap { ReviewScheduler.state(of: $0, settings: settings.review, today: today).due }
    }

    func notes(for unit: FolioDomain.Unit, in courseId: UUID) -> [NoteFile] {
        guard let course = course(courseId) else { return [] }
        let sessions = course.file.sessions.filter { unit.sessionIds.contains($0.id) }
        let linked = Set(sessions.flatMap { [$0.roughNoteId, $0.reviewNoteId].compactMap { $0 } })
        let rank: [NoteKind: Int] = [.review: 0, .rough: 1]
        return ((try? course.store.notes()) ?? [])
            .filter { n in
                n.meta.id.map(linked.contains) == true || n.meta.unitIds.contains(unit.id)
                    || n.meta.sessionId.map(unit.sessionIds.contains) == true
            }
            .sorted { a, b in
                let (ra, rb) = (rank[a.meta.kind] ?? 2, rank[b.meta.kind] ?? 2)
                return ra != rb ? ra < rb : a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
    }

    /// Marks units as not needing review, one `skip` event each, with no study time.
    func skipReviews(_ units: [(courseId: UUID, unitId: UUID)]) {
        run(ReviewSkip(units: units.map { ReviewSkip.Target(course: $0.courseId, unit: $0.unitId) }))
    }

    func recordReview(course courseId: UUID, unit: UUID, result: ReviewResult, start: Date, end: Date) {
        run(ReviewRecord(course: courseId, unit: unit, result: result, start: start, end: end))
    }
}
