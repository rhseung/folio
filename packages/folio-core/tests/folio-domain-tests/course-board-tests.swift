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
    /// now; only a topic note's own units count, and a stored copy on another kind is ignored.
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
                              notes: [stale, entry(topic, .topic, units: [tested.id]), entry(summary, .examSummary, exam: exam.id), entry(loose, .rough)])
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
}
