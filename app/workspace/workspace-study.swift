import FolioActions
import FolioCore
import FolioDomain
import FolioMarkdown
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

    // 노트 블록에서 만든 카드 중 원본 블록이 바뀐 카드다. 노트 파일을 읽으므로 화면은 `notesRevision`이나 `studyRevision`이
    // 바뀔 때만 다시 부른다. 카드 화면과 단원 페이지가 함께 쓴다.
    func changedCardSources(in courseId: UUID) -> Set<UUID> {
        guard let course = course(courseId), let study = study(of: courseId) else { return [] }
        let cards = study.allCards.map(\.card).filter { $0.noteBlockHash != nil }
        guard !cards.isEmpty else { return [] }
        let notes = (try? course.store.notes()) ?? []
        var texts: [UUID: String] = [:]
        for id in Set(cards.compactMap(\.noteId)) {
            if let note = notes.first(where: { $0.meta.id == id }) { texts[id] = try? course.store.read(note) }
        }
        return Set(
            cards.filter { card in
                let text = card.noteId.flatMap { texts[$0] }
                return card.sourceChanged(block: card.noteBlockId.flatMap { id in text.flatMap { NoteBlockCard.source(of: id, in: $0) } })
            }
            .map(\.id))
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

    // 공부일이 바뀌거나 계획의 기준(범위, 시험 날짜, 공부 설정)이 바뀌면 다가오는 시험의 계획을 지금 준비로 다시 짠다(#578).
    // 같은 공부일에 같은 기준으로 짠 시험은 건너뛰므로 여러 번 불러도 한 번만 쓴다.
    func replanExams() {
        let today = self.today
        for course in currentCourses {
            for exam in course.file.exams where course.file.needsPlan(exam, today: today, settings: settings, calendar: calendar) {
                _ = try? runThrowing(ExamPlanMake(course: course.id, exam: exam.id))
            }
        }
    }

    // 다시 짜야 하는지 볼 값이다. 앱이 이 값을 지켜보다 바뀌면 `replanExams`를 부른다.
    var planBases: [ExamPlanBasis] {
        currentCourses.flatMap { c in c.file.exams.map { ExamPlanBasis(exam: $0, in: c.file, settings: settings, calendar: calendar) } }
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
