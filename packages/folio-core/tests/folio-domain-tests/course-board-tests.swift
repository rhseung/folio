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
        var exam = Exam(device: device, at: now, kind: .midterm, title: "", start: now - 7200, end: now - 60)
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

    @Test func aNoteBelongsToTheSessionPointingAtItBeforeItsFrontmatter() {
        let note = UUID()
        var pointing = Session(device: device, at: now, week: 3, index: 1, date: now)
        pointing.reviewNoteId = note
        let named = Session(device: device, at: now, week: 2, index: 1, date: now)
        let file = CourseFile(course: Course(device: device, at: now, title: ""), sessions: [named, pointing])
        #expect(file.session(of: NoteMeta(id: note, kind: .review, sessionId: named.id))?.id == pointing.id)
        #expect(file.session(of: NoteMeta(id: UUID(), kind: .rough, sessionId: named.id))?.id == named.id)
        #expect(file.session(of: NoteMeta(id: nil, kind: .rough)) == nil)
        #expect(file.session(pointingAt: nil) == nil)
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
