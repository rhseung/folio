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
        #expect(f.wrapUpGaps(of: f.sessions[0]) == [.progress, .units, .topic, .note, .attendance])
        // No lecture file, no progress to ask about.
        let g = course(lectures: false)
        #expect(g.wrapUpGaps(of: g.sessions[0]) == [.units, .topic, .note, .attendance])
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
        f.sessions[0].topic = "  "
        #expect(f.wrapUpGaps(of: f.sessions[0]) == [.topic, .note, .attendance])
        f.sessions[0].topic = "홀의 정리"
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
        f.sessions[0].topic = "매칭"
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

    @Test func theLastClassesUnitsComeFirstButAreNotChosen() {
        var f = course()
        let earlier = Session(device: device, at: at(1, 9), week: 9, date: at(1, 10, 30))
        f.sessions.append(earlier)
        let a = FolioDomain.Unit(device: device, at: at(1, 9), title: "매칭", order: 0, parentId: nil)
        f.units = [a]
        #expect(f.recentUnits(before: f.sessions[0]).isEmpty)
        f.toggle(session: earlier.id, unit: a.id)
        #expect(f.recentUnits(before: f.sessions[0]) == [a.id])
        #expect(f.sessions[0].unitIds.isEmpty)
    }
}
