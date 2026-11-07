import FolioDomain
import Foundation
import PropertyBased
import Testing

/// How a class is named on the command line, in files and on screen now that it isn't `9주차-2`.
struct SessionReferenceTests {
    let device = UUID()
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func at(_ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 30, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func session(_ date: Date, made: Date? = nil, topic: String = "") -> Session {
        var s = Session(device: device, at: made ?? date, week: 1, date: date)
        s.topic = topic
        return s
    }

    func file(_ sessions: [Session]) -> CourseFile {
        CourseFile(course: Course(device: device, at: .now, title: "그래프 이론"), sessions: sessions)
    }

    @Test func aClassIsItsDay() {
        let tue = session(at(11, 3), topic: "Matchings")
        let f = file([tue, session(at(11, 5))])
        #expect(f.reference(of: tue, calendar: calendar) == "11-03")
        #expect(f.title(of: tue, calendar: calendar) == "11/3(화): Matchings")
        #expect(f.recordingName(of: tue, calendar: calendar) == "11-03(화)")
        #expect(f.references(of: tue, calendar: calendar) == ["11-03", "11/3", "11-03", "2026-11-03", "Matchings"])
    }

    /// A lecture and a lab the same day both take their start, and the day alone picks neither.
    @Test func twoClassesOneDayTakeTheirTimes() {
        let lecture = session(at(11, 3, 10, 30)), lab = session(at(11, 3, 14, 0))
        let f = file([lab, lecture])
        #expect(f.reference(of: lecture, calendar: calendar) == "11-03 10:30")
        #expect(f.reference(of: lab, calendar: calendar) == "11-03 14:00")
        #expect(f.sessions(matching: "11/3", calendar: calendar).map(\.id) == [lecture.id, lab.id])
        #expect(f.sessions(matching: "11-03 14:00", calendar: calendar).map(\.id) == [lab.id])
        #expect(f.sessions(matching: "11-0314:00", calendar: calendar).map(\.id) == [lab.id])
    }

    /// A makeup the same evening as a cancelled class is a second class that day: the cancelled one stays a class.
    @Test func aMakeupBesideACancelledClass() {
        var cancelled = session(at(11, 3, 10, 30))
        cancelled.isCancelled = true
        let makeup = session(at(11, 3, 21, 0), made: at(11, 1))
        let other = session(at(11, 5))
        let f = file([cancelled, makeup, other])
        #expect(f.reference(of: cancelled, calendar: calendar) == "11-03 10:30")
        #expect(f.reference(of: makeup, calendar: calendar) == "11-03 21:00")
        // Unlike 10주차-1 and 10주차-2, a makeup leaves the other days' classes as they were.
        #expect(f.reference(of: other, calendar: calendar) == "11-05")
        // A session not yet in the file is named where its date puts it.
        let more = session(at(11, 5, 19, 0))
        #expect(f.reference(of: more, calendar: calendar) == "11-05 19:00")
    }

    /// Date-only imports put two classes at midnight: they take the time all the same, since the day alone names both,
    /// and count on in the order they were made, as file names do.
    @Test func classesAtOneMinuteCountOn() {
        let first = session(at(11, 3, 0, 0), made: at(9, 1)), second = session(at(11, 3, 0, 0), made: at(9, 2))
        let f = file([second, first])
        #expect(f.reference(of: first, calendar: calendar) == "11-03 00:00")
        #expect(f.reference(of: second, calendar: calendar) == "11-03 00:00 2")
        #expect(f.sessions(matching: "11-03", calendar: calendar).count == 2)
        let evening = session(at(11, 3, 19, 0))
        let g = file([second, first, evening])
        #expect([first, second, evening].map { g.reference(of: $0, calendar: calendar) } == ["11-03 00:00", "11-03 00:00 2", "11-03 19:00"])
    }

    /// A course over New Year that meets on the same month and day twice tells them apart by the year.
    @Test func theSameDayAYearApart() {
        let a = session(at(1, 5, year: 2026)), b = session(at(1, 5, year: 2027))
        let f = file([a, b])
        #expect(f.reference(of: a, calendar: calendar) == "2026-01-05" && f.reference(of: b, calendar: calendar) == "2027-01-05")
    }

    /// The calendar day, as the note's file name has it: a class at 1:00 is the 4th, though the study day is the 3rd.
    @Test func theCalendarDayNotTheStudyDay() {
        let late = session(at(11, 3, 23, 30)), night = session(at(11, 4, 1, 0))
        let f = file([late, night])
        #expect(f.reference(of: late, calendar: calendar) == "11-03")
        #expect(f.reference(of: night, calendar: calendar) == "11-04")
        #expect(f.noteTitle(for: night, kind: .rough, calendar: calendar) == "11-04(수)")
        #expect(f.recordingName(of: night, calendar: calendar) == "11-04(수)")
    }

    @Test func aNotesSpanIsItsDays() {
        let note = UUID()
        var a = session(at(11, 3)), b = session(at(11, 10))
        a.reviewNoteId = note
        #expect(file([a, b]).sessionSpan(of: note, calendar: calendar) == "11/3(화)")
        b.reviewNoteId = note
        #expect(file([a, b]).sessionSpan(of: note, calendar: calendar) == "11/3(화) – 11/10(화)")
    }

    /// Only recordings still named the old way, and of a class, are renamed.
    @Test func oldRecordingNames() {
        let s = session(at(11, 3))
        var f = file([s])
        let old = Recording(device: device, at: .now, sessionId: s.id, file: "Recordings/10주차-1.m4a")
        let second = Recording(device: device, at: .now, sessionId: s.id, file: "Recordings/10주차-1 2.m4a")
        let mine = Recording(device: device, at: .now, sessionId: s.id, file: "Recordings/보강.m4a")
        let loose = Recording(device: device, at: .now, sessionId: nil, file: "Recordings/3주차-1.m4a")
        let new = Recording(device: device, at: .now, sessionId: s.id, file: "Recordings/11-03(화).m4a")
        f.recordings = [old, second, mine, loose, new]
        #expect(f.legacyRecordingRetitles(calendar: calendar) == [
            RecordingRetitle(recording: old.id, file: old.file, name: "11-03(화)"),
            RecordingRetitle(recording: second.id, file: second.file, name: "11-03(화)"),
        ])
    }

    // MARK: Properties

    /// Day offsets over more than a year, so a month and day can come twice; a few starts, midnight among them, so
    /// days with two classes and classes at one minute come up often.
    static let sessions = zip(Gen.int(in: 0...400), Gen.int(in: 0...3), Gen.int(in: 0...2)).array(of: 0...12)
    static let minutes = [0, 60, 630, 840]

    func make(_ rows: [(Int, Int, Int)]) -> CourseFile {
        let start = at(3, 2, 0, 0)
        return file(rows.map { day, slot, made in
            let date = calendar.date(byAdding: .minute, value: Self.minutes[slot], to: calendar.date(byAdding: .day, value: day, to: start)!)!
            return session(date, made: start.addingTimeInterval(TimeInterval(made)))
        })
    }

    @Test func everyClassHasItsOwnReference() async {
        await propertyCheck(input: Self.sessions) { rows in
            let f = make(rows)
            let refs = f.sessions.map { f.reference(of: $0, calendar: calendar) }
            #expect(Set(refs).count == refs.count)
        }
    }

    @Test func aReferenceFindsItsClassAlone() async {
        await propertyCheck(input: Self.sessions) { rows in
            let f = make(rows)
            for s in f.sessions { #expect(f.sessions(matching: f.reference(of: s, calendar: calendar), calendar: calendar).map(\.id) == [s.id]) }
        }
    }

    /// Classes on other days never change a class's reference, as a makeup used to renumber the whole week.
    @Test func onlyItsOwnDayMovesAReference() async {
        await propertyCheck(input: Self.sessions) { rows in
            let f = make(rows)
            for s in f.sessions {
                let d = calendar.dateComponents([.month, .day], from: s.date)
                let sameDay = f.sessions.filter { calendar.dateComponents([.month, .day], from: $0.date) == d }
                #expect(file(sameDay).reference(of: s, calendar: calendar) == f.reference(of: s, calendar: calendar))
            }
        }
    }

    /// The reference starts with the day the class's note and recording are named for.
    @Test func theReferenceIsTheFilesDay() async {
        await propertyCheck(input: Self.sessions) { rows in
            let f = make(rows)
            for s in f.sessions {
                let day = String(f.recordingName(of: s, calendar: calendar).prefix(5))
                let ref = f.reference(of: s, calendar: calendar)
                #expect(ref.hasPrefix(day) || ref.dropFirst(5).hasPrefix(day))
                #expect(f.noteTitle(for: s, kind: .rough, calendar: calendar).hasPrefix(day))
            }
        }
    }
}
