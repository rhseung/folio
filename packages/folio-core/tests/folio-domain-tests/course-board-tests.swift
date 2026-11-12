import FolioDomain
import Foundation
import Testing

struct CourseBoardTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }

    @Test func examIsOverWhenItEndsNotWhenTheDayTurns() {
        let today = LocalDate(now, in: calendar)
        var exam = Exam(device: device, at: now, title: "", start: now - 7200, end: now - 60)
        #expect(exam.isOver(now: now, today: today, calendar: calendar))
        exam.end = now + 60
        #expect(!exam.isOver(now: now, today: today, calendar: calendar))
        // Without an end, an exam started earlier today is still today's.
        exam.end = nil
        #expect(!exam.isOver(now: now, today: today, calendar: calendar))
        exam.start = now - 86_400
        #expect(exam.isOver(now: now, today: today, calendar: calendar))
        exam.start = nil
        #expect(!exam.isOver(now: now, today: today, calendar: calendar))
    }

    @Test func assignmentsGroupByStatusThenDeadline() {
        var late = Assignment(device: device, at: now, title: "B", due: now - 60)
        let open = Assignment(device: device, at: now, title: "A", due: now + 60)
        let undated = Assignment(device: device, at: now, title: "C")
        #expect(AssignmentGroup(late, now: now) == .overdue)
        #expect(AssignmentGroup(open, now: now) == .open)
        #expect(AssignmentGroup(undated, now: now) == .open)
        late.status = .submitted
        #expect(AssignmentGroup(late, now: now) == .submitted)
        late.status = .graded
        #expect(AssignmentGroup(late, now: now) == .graded)

        #expect(AssignmentGroup.open.sorted([undated, open]).map(\.title) == ["A", "C"])
        let older = Assignment(device: device, at: now, title: "D", due: now - 86_400)
        #expect(AssignmentGroup.graded.sorted([older, late, undated]).map(\.title) == ["B", "D", "C"])
    }

    /// A note's session is the one pointing at it, and its units follow that session or its exam's scope as they are
    /// now; only a unit note's own units count, and a stored copy on another kind is ignored.
    @Test func aNotesLinksAreReadFromItsSessionAndExam() {
        let review = UUID(), topic = UUID(), summary = UUID(), loose = UUID()
        var taught = Unit(device: device, at: now, title: "매칭", order: 0)
        let tested = Unit(device: device, at: now, title: "트리", order: 1)
        var session = Session(device: device, at: now, week: 3, date: now)
        session.reviewNoteId = review
        session.unitIds = [taught.id]
        taught.sessionIds = [session.id]
        var exam = Exam(device: device, at: now, title: "중간")
        exam.scopeUnitIds = [tested.id]
        func entry(_ id: UUID, _ kind: NoteKind, units: [UUID] = [], exam: UUID? = nil) -> NoteEntry {
            NoteEntry(id: id, device: device, at: now, path: "Notes/\(id).md", meta: NoteMeta(id: id, kind: kind, unitIds: units, examId: exam))
        }
        var stale = entry(review, .review)
        stale.unitIds = [tested.id]
        let file = CourseFile(course: Course(device: device, at: now, title: ""), units: [taught, tested], sessions: [session], exams: [exam],
                              notes: [stale, entry(topic, .unit, units: [tested.id]), entry(summary, .examSummary, exam: exam.id), entry(loose, .rough)])
        let meta = Dictionary(uniqueKeysWithValues: file.notes.map { ($0.id, file.meta(of: $0)) })
        #expect(meta[review]?.sessionId == session.id && meta[review]?.unitIds == [taught.id])
        #expect(meta[topic]?.unitIds == [tested.id] && meta[topic]?.sessionId == nil)
        #expect(meta[summary]?.unitIds == [tested.id])
        #expect(meta[loose]?.sessionId == nil && meta[loose]?.unitIds == [])
        #expect(file.sessions(pointingAt: nil).isEmpty)
    }

    @Test func reviewOnTrackNeedsANoteAndAFutureDueDay() {
        let today = LocalDate("2026-10-20")!
        let unit = UUID()
        #expect(ReviewState(unitId: unit, step: 0, due: today, settled: false, writeNoteFirst: false).isOnTrack(today: today))
        #expect(ReviewState(unitId: unit, step: 0, due: nil, settled: true, writeNoteFirst: false).isOnTrack(today: today))
        #expect(!ReviewState(unitId: unit, step: 0, due: LocalDate("2026-10-19")!, settled: false, writeNoteFirst: false).isOnTrack(today: today))
        #expect(!ReviewState(unitId: unit, step: 0, due: today, settled: false, writeNoteFirst: true).isOnTrack(today: today))
    }

    // MARK: Notes page

    struct Listed {
        var meta: NoteMeta
        var title: String
    }

    func titles(_ group: NoteGroup, _ notes: [Listed], in file: CourseFile) -> [String] {
        group.sorted(notes, meta: \.meta, title: \.title, in: file).map(\.title)
    }

    /// The newest class first, a review note covering several classes at the last of them, the rough note before the
    /// review note of one class, and notes without a class last, rough first and then by title.
    @Test func classNotesSortByTheirLatestClass() {
        let notes = [
            Listed(meta: NoteMeta(kind: .rough), title: "둘째 러프"),
            Listed(meta: NoteMeta(kind: .review), title: "밀린 복습"),
            Listed(meta: NoteMeta(kind: .rough), title: "셋째 러프"),
            Listed(meta: NoteMeta(kind: .review), title: "가 복습"),
            Listed(meta: NoteMeta(kind: .rough), title: "다 러프"),
            Listed(meta: NoteMeta(kind: .rough), title: "나 러프"),
        ]
        var sessions = (1...3).map { Session(device: device, at: now, week: $0, date: now + Double($0) * 86_400) }
        sessions[1].roughNoteId = notes[0].meta.id
        sessions[0].reviewNoteId = notes[1].meta.id
        sessions[2].reviewNoteId = notes[1].meta.id
        sessions[2].roughNoteId = notes[2].meta.id
        let file = CourseFile(course: Course(device: device, at: now, title: ""), sessions: sessions)
        #expect(titles(.classes, notes, in: file) == ["셋째 러프", "밀린 복습", "둘째 러프", "나 러프", "다 러프", "가 복습"])
    }

    /// The next exam first; a summary of an exam without a start, or of none, after every dated one, by title.
    @Test func examSummariesSortByTheExamsStart() {
        let later = Exam(device: device, at: now, title: "기말", start: now + 5 * 86_400)
        let sooner = Exam(device: device, at: now, title: "중간", start: now + 86_400)
        let undated = Exam(device: device, at: now, title: "퀴즈")
        let notes = [
            Listed(meta: NoteMeta(kind: .examSummary, examId: later.id), title: "기말 정리"),
            Listed(meta: NoteMeta(kind: .examSummary), title: "정리 B"),
            Listed(meta: NoteMeta(kind: .examSummary, examId: undated.id), title: "정리 A"),
            Listed(meta: NoteMeta(kind: .examSummary, examId: sooner.id), title: "중간 정리"),
        ]
        let file = CourseFile(course: Course(device: device, at: now, title: ""), exams: [later, sooner, undated])
        #expect(titles(.exams, notes, in: file) == ["중간 정리", "기말 정리", "정리 A", "정리 B"])
    }

    /// Titles compare as Finder does, so `노트 2` comes before `노트 10`; empty groups are left out and the rest keep the
    /// page's order whatever order the notes come in.
    @Test func notesGroupInPageOrder() {
        let notes = [
            Listed(meta: NoteMeta(kind: .free), title: "노트 10"),
            Listed(meta: NoteMeta(kind: .unit), title: "단원"),
            Listed(meta: NoteMeta(kind: .free), title: "노트 2"),
            Listed(meta: NoteMeta(kind: .rough), title: "러프"),
        ]
        let file = CourseFile(course: Course(device: device, at: now, title: ""))
        let grouped = NoteGroup.grouped(notes, meta: \.meta, title: \.title, in: file)
        #expect(grouped.map(\.group) == [.classes, .units, .free])
        #expect(grouped.last?.notes.map(\.title) == ["노트 2", "노트 10"])
        #expect(NoteKind.allCases.map(NoteGroup.init) == [.classes, .classes, .exams, .units, .free])
    }

    /// A unit note's units come in outline order, a chapter's units right under it, not in the order the note lists them.
    @Test func aUnitNotesUnitsFollowTheOutline() {
        let chapter = Unit(device: device, at: now, title: "장", order: 1)
        let inner = Unit(device: device, at: now, title: "절", order: 0, parentId: chapter.id)
        let first = Unit(device: device, at: now, title: "처음", order: 0)
        let file = CourseFile(course: Course(device: device, at: now, title: ""), units: [inner, chapter, first])
        #expect(file.units(of: NoteMeta(kind: .unit, unitIds: [inner.id, first.id])).map(\.title) == ["처음", "절"])
        #expect(file.units(of: NoteMeta(kind: .unit, unitIds: [chapter.id, inner.id])).map(\.title) == ["장", "절"])
    }
}
