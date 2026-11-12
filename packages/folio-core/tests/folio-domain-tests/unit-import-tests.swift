import FolioDomain
import Foundation
import Testing

struct UnitImportTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func day(_ month: Int, _ day: Int, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: 30))!
    }

    /// Units link to sessions on both sides, an existing unit keeps its ID, and a second run changes nothing. Sessions
    /// are named as the command line names them; the old `2주차-1` names nothing.
    @Test func addsUnitsLinksSessionsAndIsIdempotent() {
        let s1 = Session(device: device, at: now, week: 2, date: day(9, 8))
        let s2 = Session(device: device, at: now, week: 3, date: day(9, 15))
        let trees = Unit(device: device, at: now, title: "Trees", order: 0)
        let file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"), units: [trees], sessions: [s1, s2])
        let specs = [
            UnitSpec(title: "Trees", sessions: ["09-08"], children: [UnitSpec(title: "Spanning trees", sessions: ["9/15", "2주차-1"])]),
            UnitSpec(title: "Matchings"),
        ]
        let r = UnitImporter.merge(specs, into: file, calendar: calendar, device: device, now: now)

        #expect(r.added == ["Spanning trees", "Matchings"])
        #expect(r.unknownSessions == ["2주차-1"])
        let spanning = r.file.units.first { $0.title == "Spanning trees" }!
        #expect(spanning.parentId == trees.id)
        #expect(r.file.units.first { $0.title == "Matchings" }?.order == 1)
        #expect(r.file.units.first { $0.id == trees.id }?.sessionIds == [s1.id])
        #expect(r.file.sessions.first { $0.id == s2.id }?.unitIds == [spanning.id])
        let again = UnitImporter.merge(specs, into: r.file, calendar: calendar, device: device, now: now)
        #expect(again.added.isEmpty && again.linked.isEmpty)
    }

    /// A day with two classes names neither, so nothing is linked by guess; the start picks one.
    @Test func aDayWithTwoClassesNeedsTheTime() {
        let lecture = Session(device: device, at: now, week: 2, date: day(9, 8))
        let lab = Session(device: device, at: now, week: 2, date: day(9, 8, 14))
        let file = CourseFile(course: Course(device: device, at: now, title: "물리"), sessions: [lecture, lab])
        let r = UnitImporter.merge([UnitSpec(title: "역학", sessions: ["09-08", "09-08 14:30"])], into: file, calendar: calendar, device: device, now: now)
        #expect(r.unknownSessions == ["09-08"])
        #expect(r.file.units.first?.sessionIds == [lab.id])
    }
}

struct ExamScopeTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_000_000)

    /// Everything taught before the midterm is its scope: covered sections bring their chapter; later and cancelled classes don't count.
    @Test func midtermScopeIsWhatWasTaughtBeforeIt() {
        let before = Session(device: device, at: now, week: 2, date: now - 86_400)
        var cancelled = Session(device: device, at: now, week: 3, date: now - 3600)
        cancelled.isCancelled = true
        let after = Session(device: device, at: now, week: 9, date: now + 86_400)
        let chapter = Unit(device: device, at: now, title: "Ch1", order: 0)
        var section = Unit(device: device, at: now, title: "1.1", order: 0, parentId: chapter.id)
        section.sessionIds = [before.id]
        var skipped = Unit(device: device, at: now, title: "1.2", order: 1, parentId: chapter.id)
        skipped.sessionIds = [cancelled.id]
        var later = Unit(device: device, at: now, title: "Ch2", order: 1)
        later.sessionIds = [after.id]
        let exam = Exam(device: device, at: now, title: "Midterm", start: now)
        var file = CourseFile(course: Course(device: device, at: now, title: ""), units: [later, section, chapter, skipped], sessions: [before, cancelled, after], exams: [exam])

        let taught = file.unitsTaught(before: exam.start!)
        #expect(taught == [chapter.id, section.id])
        #expect(file.addScope(taught, exam: exam.id) == taught)
        #expect(file.units.first { $0.id == section.id }?.examIds == [exam.id])
        #expect(file.addScope(taught, exam: exam.id).isEmpty)
    }
}
