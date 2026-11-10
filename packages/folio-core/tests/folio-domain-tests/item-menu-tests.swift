import FolioDomain
import Foundation
import PropertyBased
import Testing

struct ItemMenuTests {
    let device = UUID()
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// Mondays 10:30–11:45 with a Zoom link, one lecture file, and the class of Monday 11/2.
    func course() -> CourseFile {
        var file = CourseFile(course: Course(device: device, at: at(1, 9), title: "그래프 이론"))
        file.course.schedule = [ClassTime(weekday: 1, startMinute: 630, endMinute: 705, link: "https://zoom.us/j/1")]
        file.materials = [Material(device: device, at: at(1, 9), path: "Lectures/05_Matchings.pdf", role: .lecture, status: .classified)]
        file.sessions = [Session(device: device, at: at(1, 9), week: 10, date: at(2, 10, 30))]
        return file
    }

    func commands(_ f: CourseFile, at now: Date, host: MenuHost = .own) -> [SessionCommand] {
        f.commands(for: f.sessions[0], at: now, host: host, classMinutes: 75, calendar: calendar)
    }

    func recording(_ f: CourseFile, _ minutes: Int) -> Recording {
        Recording(device: device, at: at(2, 12, minutes), sessionId: f.sessions[0].id, file: "Recordings/\(minutes).m4a", duration: 600)
    }

    // MARK: Order

    @Test func groupsKeepTheirOrderAndRemoveIsLast() {
        #expect(MenuGroup.allCases == [.open, .start, .state, .edit, .arrange, .share, .remove])
        #expect(MenuGroup.allCases.map(\.band) == [0, 0, 0, 1, 1, 1, 2])
        let shuffled: [SessionCommand] = [.remove, .share, .edit, .review(.needed), .record, .join, .open, .unlink(unit: UUID())]
        #expect(shuffled.inMenuOrder().map(\.group) == [.open, .open, .start, .state, .edit, .arrange, .share, .remove])
    }

    /// Whatever the class holds and whenever the menu opens, rows come by group, delete last, edit and share always.
    @Test func everyMenuIsInGroupOrderWithDeleteLast() async {
        await propertyCheck(input: Gen.int(in: 0...(7 * 24 * 4)), Gen.int(in: 0...3), Gen.int(in: 0...3), Gen.int(in: 0...2)) { quarter, recorded, flags, host in
            var f = course()
            f.sessions[0].roughNoteId = flags & 1 == 1 ? UUID() : nil
            f.sessions[0].isCancelled = flags & 2 == 2
            f.recordings = (0..<recorded).map { recording(f, $0) }
            let hosts: [MenuHost] = [.own, .elsewhere, .unit(UUID())]
            let now = at(1, 0).addingTimeInterval(TimeInterval(quarter * 15 * 60))
            let menu = commands(f, at: now, host: hosts[host])
            #expect(menu.map(\.group) == menu.map(\.group).sorted())
            #expect(menu.last == .remove)
            #expect(menu.filter { $0 == .remove }.count == 1)
            #expect(menu.contains(.edit) && menu.contains(.share))
        }
    }

    // MARK: A class's rows over time

    @Test func aheadAndUnderWayOfferJoiningTheNoteAndRecording() {
        var f = course()
        #expect(commands(f, at: at(2, 9)) == [.join, .record, .edit, .share, .remove])
        // Under way, with a rough note: opening it joins the join row.
        f.sessions[0].roughNoteId = UUID()
        #expect(commands(f, at: at(2, 11, 44)) == [.join, .openNote(.rough), .record, .edit, .share, .remove])
        // Off the screen of its own, opening the class leads.
        #expect(commands(f, at: at(2, 9), host: .elsewhere).first == .open)
    }

    @Test func afterTheClassItsNotesReviewAndRecordings() {
        var f = course()
        // The end is the moment it flips: 11:45.
        #expect(commands(f, at: at(2, 11, 45)) == [.makeReviewNote, .review(.needed), .edit, .share, .remove])
        f.sessions[0].roughNoteId = UUID()
        f.sessions[0].reviewNoteId = UUID()
        f.sessions[0].reviewNoteUnfinished = true
        f.recordings = [recording(f, 0)]
        #expect(commands(f, at: at(2, 12)) == [.openNote(.rough), .openNote(.review), .play(f.recordings[0].id), .review(.writing), .edit, .share, .remove])
        f.recordings.append(recording(f, 1))
        #expect(commands(f, at: at(2, 12)).contains(.recordings(f.recordings.map(\.id))))
    }

    @Test func noReviewRowsForACancelledClassOrACourseOutOfReview() {
        var f = course()
        f.sessions[0].isCancelled = true
        #expect(commands(f, at: at(2, 9)) == [.edit, .share, .remove])
        #expect(commands(f, at: at(2, 12)) == [.edit, .share, .remove])
        f.sessions[0].isCancelled = false
        f.course.reviews = false
        #expect(commands(f, at: at(2, 12)) == [.edit, .share, .remove])
    }

    @Test func aUnitPageAddsUnlinkOnlyForItsOwnUnit() {
        var f = course()
        let unit = FolioDomain.Unit(device: device, at: at(1, 9), title: "매칭", order: 0, parentId: nil)
        f.units = [unit]
        f.toggle(session: f.sessions[0].id, unit: unit.id)
        #expect(commands(f, at: at(2, 9), host: .unit(unit.id)) == [.open, .join, .record, .edit, .unlink(unit: unit.id), .share, .remove])
        #expect(!commands(f, at: at(2, 9), host: .unit(UUID())).contains { if case .unlink = $0 { true } else { false } })
    }

    // MARK: Review

    @Test func theReviewCheckTogglesWithinWhatTheNoteAllows() {
        var f = course()
        #expect(f.review(of: f.sessions[0]) == .needed)
        f.sessions[0].skipsReview = true
        #expect(f.review(of: f.sessions[0]) == .notNeeded)
        f.sessions[0].reviewNoteId = UUID()
        f.sessions[0].reviewNoteUnfinished = true
        #expect(f.review(of: f.sessions[0]) == .writing)
        for review in ClassReview.allCases {
            #expect(review.toggled.toggled == review)
            #expect(review.choices.contains(review.toggled))
            #expect(review.isChecked != review.toggled.isChecked)
            // Each value writes exactly one of the two flags.
            #expect((review.skipsReview == nil) != (review.reviewUnfinished == nil))
        }
    }

    // MARK: The sheet

    @Test func theSheetPutsWhatTheClassCoveredFirstOnceItBegan() {
        let f = course()
        let s = f.sessions[0]
        #expect(f.sections(of: s, kind: .lecture, start: s.date, at: at(2, 12), takesAttendance: true) == [.progress, .units, .notes, .attendance, .info])
        #expect(f.sections(of: s, kind: .lecture, start: s.date, at: at(2, 9), takesAttendance: true) == [.info, .units, .notes, .attendance])
        #expect(f.sections(of: s, kind: .cancelled, start: s.date, at: at(2, 12), takesAttendance: true) == [.info])
        #expect(f.sections(of: nil, kind: .makeup, start: s.date, at: at(2, 12), takesAttendance: false) == [.info, .units])
        var g = f
        g.materials = []
        #expect(g.sections(of: s, kind: .lecture, start: s.date, at: at(2, 12), takesAttendance: false) == [.units, .notes, .info])
    }

    /// A save during the class (linking its units ahead, 2026-11-10) leaves it to be asked about once it ends. A
    /// stopped recording's prompt is the wrap-up, whenever it comes.
    @Test func savingWrapsUpAnEndedOrRecordedHeldClassOnly() {
        var f = course()
        let wraps = { (f: CourseFile, now: Date) in f.savingWrapsUp(f.sessions[0], at: now, classMinutes: 75, calendar: calendar) }
        #expect(!wraps(f, at(2, 10, 29)))
        #expect(!wraps(f, at(2, 10, 30)))
        #expect(!wraps(f, at(2, 11, 44)))
        #expect(wraps(f, at(2, 11, 45)))
        // A recording just stopped, not in the course yet: its prompt passes it.
        #expect(f.savingWrapsUp(f.sessions[0], recorded: true, at: at(2, 11), classMinutes: 75, calendar: calendar))
        f.recordings = [recording(f, 0)]
        #expect(wraps(f, at(2, 11)))
        f.sessions[0].kind = .makeup
        #expect(wraps(f, at(2, 12)))
        f.sessions[0].kind = .cancelled
        #expect(!wraps(f, at(2, 12)))
    }
}
