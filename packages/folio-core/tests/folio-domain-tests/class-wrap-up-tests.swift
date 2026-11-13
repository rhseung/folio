import FolioDomain
import Foundation
import PropertyBased
import Testing

struct ClassWrapUpTests {
    let device = UUID()
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// Mondays and Wednesdays 10:30–11:45, one lecture file, and the class of Monday 11/2.
    func course(lectures: Bool = true) -> CourseFile {
        var file = CourseFile(course: Course(device: device, at: at(1, 9), title: "그래프 이론"))
        file.course.schedule = [ClassTime(weekday: 1, startMinute: 630, endMinute: 705), ClassTime(weekday: 3, startMinute: 630, endMinute: 705)]
        file.materials = (lectures ? ["Lectures/05_Matchings.pdf"] : ["Textbooks/West.pdf"]).map {
            Material(device: device, at: at(1, 9), path: $0, role: MaterialRole(path: $0), status: .classified)
        }
        file.sessions = [Session(device: device, at: at(1, 9), week: 10, date: at(2, 10, 30))]
        return file
    }

    // MARK: What a class is missing

    @Test func anEmptyClassMissesEverythingInAskingOrder() {
        let f = course()
        #expect(f.wrapUpGaps(of: f.sessions[0]) == [.progress, .units, .note, .attendance])
        // No lecture file, no progress to ask about.
        let g = course(lectures: false)
        #expect(g.wrapUpGaps(of: g.sessions[0]) == [.units, .note, .attendance])
    }

    @Test func eachItemIsFilledByWhatItAsks() {
        var f = course()
        let s = f.sessions[0].id

        // A link without pages names the file but not how far the class went.
        f.linkMaterial(f.materials[0].id, session: s)
        #expect(f.wrapUpGaps(of: f.sessions[0]).first == .progress)

        f.linkMaterial(f.materials[0].id, session: s, firstPage: 7, lastPage: 11)
        let unit = FolioDomain.Unit(device: device, at: at(1, 9), title: "매칭", order: 0, parentId: nil)
        f.units = [unit]
        f.toggle(session: s, unit: unit.id)
        #expect(f.wrapUpGaps(of: f.sessions[0]) == [.note, .attendance])

        // A review note is a written-up class too.
        f.sessions[0].reviewNoteId = UUID()
        #expect(f.wrapUpGaps(of: f.sessions[0]) == [.attendance])
    }

    @Test func attendanceIsKnownFromARecordingAnEntryOrASavedWrapUp() {
        var f = course()
        #expect(!f.attendanceKnown(of: f.sessions[0]))
        #expect(f.attendanceKnown(of: f.sessions[0], recorded: true))
        f.recordings = [Recording(device: device, at: at(2, 11), sessionId: f.sessions[0].id, file: "Recordings/a.m4a", duration: 600)]
        #expect(f.attendanceKnown(of: f.sessions[0]))
        f.recordings = []
        f.attendance = [Attendance(device: device, at: at(2, 11), sessionId: f.sessions[0].id, state: .late)]
        #expect(f.attendanceKnown(of: f.sessions[0]))
        f.attendance = []
        f.sessions[0].isWrappedUp = true
        #expect(f.attendanceKnown(of: f.sessions[0]))
    }

    // MARK: When the today screen asks

    @Test func askedFromTheClassesEndUntilTheNextClassStarts() {
        let f = course()
        let s = f.sessions[0].id
        func asked(_ now: Date) -> Bool { f.classesToWrapUp(at: now, classMinutes: 75, calendar: calendar).map(\.id) == [s] }

        #expect(!asked(at(2, 11, 44)))
        #expect(asked(at(2, 11, 45)))

        // Over the night and the 4 a.m. day boundary: still the same class until Wednesday's starts.
        #expect(asked(at(3, 3, 59)))
        #expect(asked(at(3, 4, 0)))
        #expect(asked(at(4, 10, 29)))
        #expect(!asked(at(4, 10, 30)))
    }

    @Test func aCancelledNextClassLeavesTheAskUntilTheOneAfter() {
        var f = course()
        var off = Session(device: device, at: at(1, 9), week: 10, date: at(4, 10, 30))
        off.isCancelled = true
        f.sessions.append(off)
        let mine = f.sessions[0]

        #expect(f.nextClassStart(after: mine, calendar: calendar) == at(9, 10, 30))
        #expect(f.classesToWrapUp(at: at(5, 12), classMinutes: 75, calendar: calendar).map(\.id) == [mine.id])

        // A makeup on Thursday evening is the next class instead.
        f.sessions.append(Session(device: device, at: at(1, 9), week: 10, date: at(5, 19)))
        #expect(f.nextClassStart(after: mine, calendar: calendar) == at(5, 19))
        #expect(f.classesToWrapUp(at: at(5, 19), classMinutes: 75, calendar: calendar).isEmpty)
    }

    @Test func aWrappedUpCancelledOrCompleteClassIsNotAsked() {
        let now = at(2, 12)
        var f = course()
        f.sessions[0].isWrappedUp = true

        #expect(f.classesToWrapUp(at: now, classMinutes: 75, calendar: calendar).isEmpty)
        f.sessions[0].isWrappedUp = false
        f.sessions[0].isCancelled = true
        #expect(f.classesToWrapUp(at: now, classMinutes: 75, calendar: calendar).isEmpty)

        f.sessions[0].isCancelled = false
        let s = f.sessions[0].id
        f.linkMaterial(f.materials[0].id, session: s, firstPage: 1, lastPage: 4)
        let unit = FolioDomain.Unit(device: device, at: now, title: "매칭", order: 0, parentId: nil)
        f.units = [unit]
        f.toggle(session: s, unit: unit.id)
        f.sessions[0].roughNoteId = UUID()
        f.attendance = [Attendance(device: device, at: now, sessionId: s, state: .absent)]
        #expect(f.classesToWrapUp(at: now, classMinutes: 75, calendar: calendar).isEmpty)
    }

    /// Any moment of the week: asked exactly from the class's end (11:45 Monday) to Wednesday's start (10:30).
    @Test func askedExactlyWithinTheWindow() async {
        let f = course()
        let end = at(2, 11, 45), next = at(4, 10, 30)
        await propertyCheck(input: Gen.int(in: 0...(7 * 24 * 60))) { minutes in
            let now = at(2, 0).addingTimeInterval(TimeInterval(minutes * 60))
            let asked = !f.classesToWrapUp(at: now, classMinutes: 75, calendar: calendar).isEmpty
            #expect(asked == (end <= now && now < next))
        }
    }

    // MARK: Classes left from earlier days

    @Test func earlierClassesWithGapsAreListedOldestFirst() {
        let settings = Settings()
        var f = course()
        let monday = f.sessions[0]

        // Last week's Monday wrapped up, Wednesday cancelled and a makeup that evening never wrapped up.
        var wrapped = Session(device: device, at: at(1, 9), week: 9, date: at(2, 10, 30).addingTimeInterval(-7 * 86400))
        wrapped.isWrappedUp = true
        var cancelled = Session(device: device, at: at(1, 9), week: 9, date: at(4, 10, 30).addingTimeInterval(-7 * 86400))
        cancelled.isCancelled = true
        let lastWeek = Session(device: device, at: at(1, 9), week: 9, date: at(4, 19).addingTimeInterval(-7 * 86400))
        let today = Session(device: device, at: at(1, 9), week: 10, date: at(4, 10, 30))
        f.sessions = [today, monday, wrapped, cancelled, lastWeek]
        #expect(f.unwrappedPastSessions(at: at(4, 12), settings: settings, calendar: calendar).map(\.id) == [lastWeek.id, monday.id])

        // A class with nothing missing is done without a wrap-up.
        let s = monday.id
        f.linkMaterial(f.materials[0].id, session: s, firstPage: 1, lastPage: 4)
        let unit = FolioDomain.Unit(device: device, at: at(1, 9), title: "매칭", order: 0, parentId: nil)
        f.units = [unit]
        f.toggle(session: s, unit: unit.id)
        f.sessions[1].reviewNoteId = UUID()
        f.attendance = [Attendance(device: device, at: at(2, 12), sessionId: s, state: .late)]
        #expect(f.unwrappedPastSessions(at: at(4, 12), settings: settings, calendar: calendar).map(\.id) == [lastWeek.id])
    }

    /// A class late at night, or past midnight, belongs to the study day it began on: it is left over once the
    /// 4 a.m. boundary after it passes, never before.
    @Test func leftOverExactlyFromTheNextStudyDay() async {
        let settings = Settings()
        var f = course()
        let night = Session(device: device, at: at(1, 9), week: 10, date: at(2, 23, 30))
        let pastMidnight = Session(device: device, at: at(1, 9), week: 10, date: at(3, 1, 0))
        f.sessions = [night, pastMidnight]
        let turn = at(3, 4, 0)

        #expect(f.unwrappedPastSessions(at: at(3, 3, 59), settings: settings, calendar: calendar).isEmpty)
        #expect(f.unwrappedPastSessions(at: turn, settings: settings, calendar: calendar).count == 2)
        await propertyCheck(input: Gen.int(in: 0...(3 * 24 * 60))) { minutes in
            let now = at(2, 0).addingTimeInterval(TimeInterval(minutes * 60))
            let listed = f.unwrappedPastSessions(at: now, settings: settings, calendar: calendar).map(\.id)
            #expect(listed == (turn <= now ? [night.id, pastMidnight.id] : []))
        }
    }

    @Test func aClassNoteIsChosenFromNotesNoClassHoldsNewestFirst() {
        var f = course()
        let other = Session(device: device, at: at(1, 9), week: 9, date: at(1, 10, 30))
        f.sessions.append(other)
        func note(_ name: String, _ day: Int, _ kind: NoteKind = .rough, exam: UUID? = nil) -> NoteEntry {
            NoteEntry(id: UUID(), device: device, at: at(day, 9), path: "Notes/\(name).md", meta: NoteMeta(id: nil, kind: kind, examId: exam))
        }
        let old = note("old", 1), new = note("new", 3), held = note("held", 4), free = note("free", 2, .free)
        f.notes = [old, new, held, free, note("review", 5, .review), note("exam", 6, .examSummary, exam: UUID())]
        f.linkNote(held.id, to: other.id, as: .rough)

        #expect(f.classNoteChoices.map(\.id) == [new.id, free.id, old.id])

        // Linked to this class, it is this class's and no longer a choice.
        f.linkNote(new.id, to: f.sessions[0].id, as: .rough)
        #expect(f.classNoteChoices.map(\.id) == [free.id, old.id])
    }

    // MARK: The plain form (2026-11-08)

    /// Every row shows what the class has, so a save leaves alone what it was opened with.
    @Test func aSaveWritesOnlyTheRangesTheClassDoesNotHave() {
        let (a, b, c) = (UUID(), UUID(), UUID())
        var session = course().sessions[0]
        session.materials = [SessionMaterial(materialId: a, firstPage: 3, lastPage: 9), SessionMaterial(materialId: b)]
        let same = SessionMaterial(materialId: a, firstPage: 3, lastPage: 9)
        let moved = SessionMaterial(materialId: a, firstPage: 3, lastPage: 12)
        let paged = SessionMaterial(materialId: b, firstPage: 1, lastPage: 4)
        let new = SessionMaterial(materialId: c, firstPage: 10, lastPage: 11)

        #expect(session.changedRanges([same, paged, new]) == [paged, new])
        #expect(session.changedRanges([moved]) == [moved])
        #expect(session.changedRanges([same, SessionMaterial(materialId: b)]).isEmpty)
    }

    /// Unchecking a row drops the class's link only when the row started checked: a file linked whole starts
    /// unchecked to be kept as it is, and a suggested file the class doesn't link has no link to drop.
    @Test func anUncheckedRowDropsOnlyALinkThatStartedChecked() {
        let (a, b, c) = (UUID(), UUID(), UUID())
        var session = course().sessions[0]
        session.materials = [SessionMaterial(materialId: a, firstPage: 3, lastPage: 9), SessionMaterial(materialId: b)]
        #expect(session.droppedLinks(started: [a, c], kept: []) == [a])
        #expect(session.droppedLinks(started: [a, c], kept: [a, c]).isEmpty)
        #expect(session.droppedLinks(started: [a, b, c], kept: [c]) == [a, b])
        #expect(session.droppedLinks(started: [c], kept: []).isEmpty)
    }

    /// A file linked whole stays so unless asked: checked without an end it would hold the save.
    @Test func aWholeFileLinkStartsUncheckedUnlessSuggestedWhole() {
        let (a, b) = (UUID(), UUID())
        var session = course().sessions[0]
        session.materials = [SessionMaterial(materialId: a)]
        #expect(!session.wrapUpChecks(SessionMaterial(materialId: a, firstPage: 5), wrappingUp: true))
        #expect(!session.wrapUpChecks(SessionMaterial(materialId: a), wrappingUp: true))
        // A recording saw where the class went: both ends are known, so it is asked.
        #expect(session.wrapUpChecks(SessionMaterial(materialId: a, firstPage: 5, lastPage: 9), wrappingUp: true))
        // A new suggestion is checked even with an end missing: picking it is the question.
        #expect(session.wrapUpChecks(SessionMaterial(materialId: b, firstPage: 5), wrappingUp: true))
    }

    /// Until the class is wrapped up, the sheet is opened to link units or a note ahead (2026-11-10): a suggestion
    /// starts unchecked so it neither holds that save nor writes pages the class is still going through. The pages
    /// the class has saved are its own and stay checked.
    @Test func aSuggestionStartsCheckedOnlyWhileWrappingUp() {
        let (a, b) = (UUID(), UUID())
        var session = course().sessions[0]
        session.materials = [SessionMaterial(materialId: a, firstPage: 3, lastPage: 9)]
        let own = SessionMaterial(materialId: a, firstPage: 3, lastPage: 9)
        for suggested in [SessionMaterial(materialId: b, firstPage: 5), SessionMaterial(materialId: b, firstPage: 5, lastPage: 8),
                          SessionMaterial(materialId: a, firstPage: 3, lastPage: 12)] {
            #expect(!session.wrapUpChecks(suggested, wrappingUp: false))
            #expect(session.wrapUpChecks(suggested, wrappingUp: true))
        }

        #expect(session.wrapUpChecks(own, wrappingUp: false) && session.wrapUpChecks(own, wrappingUp: true))
    }

    /// The class (10:30–11:45) is wrapped up from its end on, by the clock rather than the study day, or once a
    /// recording of it has stopped.
    @Test func aClassIsWrappedUpFromItsEndOrItsRecording() {
        var f = course()
        let wrapping = { (f: CourseFile, now: Date, recorded: Bool) in
            f.isWrappingUp(f.sessions[0], recorded: recorded, at: now, classMinutes: 75, calendar: calendar)
        }
        #expect(!wrapping(f, at(2, 10, 30), false))
        #expect(!wrapping(f, at(2, 11, 44), false))
        #expect(wrapping(f, at(2, 11, 45), false))

        // A recording just stopped, saved or not.
        #expect(wrapping(f, at(2, 11), true))
        f.recordings = [Recording(device: device, at: at(2, 11), sessionId: f.sessions[0].id, file: "Recordings/a.m4a")]
        #expect(wrapping(f, at(2, 11), false))

        // A class with its own end ends there, not at the slot's.
        f.recordings = []
        f.sessions[0].end = at(2, 11)
        #expect(!wrapping(f, at(2, 10, 59), false))
        #expect(wrapping(f, at(2, 11), false))
    }
}
