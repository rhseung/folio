import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    func reviews(of courseId: UUID) -> [(at: Date, event: ReviewEvent)] {
        (reviewEvents[courseId] ?? []).events(ReviewEvent.self)
    }

    func reviewInputs(_ course: LoadedCourse, now: Date, extra: [(at: Date, event: ReviewEvent)] = []) -> [UnitReviewInput] {
        UnitReviewInput.all(for: course.file, reviews: reviews(of: course.id) + extra, settings: settings, calendar: calendar, now: now)
    }

    /// Scheduler state per unit. Units without a past session have no cycle yet and are missing from the result.
    func reviewStates(of courseId: UUID, now: Date) -> [UUID: ReviewState] {
        guard let course = course(courseId) else { return [:] }
        let today = settings.studyDay(of: now, calendar: calendar)
        return Dictionary(keepingFirst: reviewInputs(course, now: now).map {
            ($0.unitId, ReviewScheduler.state(of: $0, settings: settings.review, today: today))
        })
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
}
