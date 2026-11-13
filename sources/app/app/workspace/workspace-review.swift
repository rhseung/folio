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

    func reviewStates(of courseId: UUID, now: Date) -> [UUID: ReviewState] {
        guard let course = course(courseId) else { return [:] }
        let today = settings.studyDay(of: now, calendar: calendar)
        return Dictionary(
            keepingFirst: reviewInputs(course, now: now).map {
                ($0.unitId, ReviewScheduler.state(of: $0, settings: settings.review, today: today))
            })
    }

    func notes(for unit: FolioDomain.Unit, in courseId: UUID) -> [NoteFile] {
        guard let course = course(courseId) else { return [] }
        let rank: [NoteKind: Int] = [.review: 0, .rough: 1]
        return ((try? course.store.notes()) ?? [])
            .filter { $0.meta.unitIds.contains(unit.id) }
            .sorted { a, b in
                let (ra, rb) = (rank[a.meta.kind] ?? 2, rank[b.meta.kind] ?? 2)
                return ra != rb ? ra < rb : a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
    }

    func skipReviews(_ units: [(courseId: UUID, unitId: UUID)]) -> PendingAction? {
        ask(ReviewSkip(units: units.map { ReviewSkip.Target(course: $0.courseId, unit: $0.unitId) }))
    }
}
