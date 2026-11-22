import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    var today: LocalDate { settings.studyDay(of: now, calendar: calendar) }
    // 분마다 움직이는 시계로 센 공부일이다. 하루 경계를 넘을 때 계획을 다시 짜는 곳만 읽는다.
    var liveToday: LocalDate { settings.studyDay(of: liveNow, calendar: calendar) }

    func isStudyToday(_ date: Date) -> Bool { settings.studyDay(of: date, calendar: calendar) == today }

    // 하루 경계가 아직 남았을 때 D-day가 자정에 바뀌지 않도록 공부일로 센다.
    func days(to date: Date) -> Int { today.days(until: LocalDate(date, in: calendar)) }

    struct StudyKey: Equatable {
        var revision: Int
        var file: CourseFile
        var today: LocalDate
        var settings: StudySettings
    }

    nonisolated static func studyEvents(_ store: CourseStore) -> [LoggedEvent] {
        (try? store.log.readAll().filter { StudyLog.types.contains($0.type) }) ?? []
    }

    // 계획 체크와 단원의 준비가 `studyRevision`을 읽어야 기록이 바뀔 때 화면이 다시 그려진다.
    func study(of courseId: UUID, now: Date? = nil) -> CourseStudy? {
        guard let course = course(courseId) else { return nil }
        let at = now ?? self.now
        let key = StudyKey(
            revision: studyRevision, file: course.file, today: settings.studyDay(of: at, calendar: calendar), settings: settings.study)
        if now == nil, let hit = studyCache[courseId], hit.key == key { return hit.study }
        let cards = course.file.units.flatMap { (try? course.store.loadCards(unit: $0.id).model.cards) ?? [] }
        let study = CourseStudy(
            file: course.file, cards: cards, log: (studyEvents[courseId] ?? []).studyLog, settings: settings, calendar: calendar, now: at)
        if now == nil { studyCache[courseId] = (key, study) }
        return study
    }

    // 공부일이 바뀐 뒤 처음 열 때 다가오는 시험의 계획을 지금 준비로 다시 짠다(#578). 같은 공부일에 이미 짠 시험은
    // 건너뛰므로 여러 번 불러도 한 번만 쓴다.
    func replanExams() {
        let today = self.today
        for course in currentCourses {
            for exam in course.file.exams where exam.planDay != today && !exam.scopeUnitIds.isEmpty {
                guard let start = exam.start, settings.studyDay(of: start, calendar: calendar) >= today else { continue }
                _ = try? runThrowing(ExamPlanMake(course: course.id, exam: exam.id))
            }
        }
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
}
