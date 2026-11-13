import FolioDomain
import Foundation
import PropertyBased
import Testing

struct ClassStartTests {
    let device = UUID()
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    // 2026년 11월 2일은 월요일이다.
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func course(_ title: String = "그래프 이론", weekday: Int = 1, start: Int = 10 * 60 + 30, end: Int = 11 * 60 + 45) -> CourseFile {
        var file = CourseFile(course: Course(device: device, at: at(1, 9), title: title))
        file.course.schedule = [ClassTime(weekday: weekday, startMinute: start, endMinute: end)]
        return file
    }

    func settings(_ change: (inout ClassStartSettings) -> Void = { $0.roughNote = .create }) -> Settings {
        var s = Settings()
        change(&s.classStart)
        return s
    }

    func starting(_ files: [CourseFile], _ settings: Settings, at now: Date, term: Semester? = nil) -> StartingClass? {
        ClassStart.starting(files.map { ClassStart.Course(file: $0, term: term) }, settings: settings, now: now, calendar: calendar)
    }

    @Test func theTimetablesClassStartsAtItsStartUntilItsEnd() throws {
        let file = course()
        let s = settings()
        #expect(starting([file], s, at: at(2, 10, 29)) == nil)
        let c = try #require(starting([file], s, at: at(2, 10, 30)))
        #expect(c == StartingClass(courseId: file.course.id, sessionId: nil, start: at(2, 10, 30), end: at(2, 11, 45)))
        #expect(ClassStart.due(c, settings: s.classStart, now: at(2, 10, 30)) == [.open])

        #expect(starting([file], s, at: at(2, 11, 44)) == c)
        #expect(starting([file], s, at: at(2, 11, 45)) == nil)
        #expect(ClassStart.due(c, settings: s.classStart, now: at(2, 11, 45)).isEmpty)
    }

    @Test func nothingStartsWhileEveryItemIsOff() {
        let file = course()
        #expect(starting([file], Settings(), at: at(2, 10, 30)) == nil)
        var s = settings()
        s.classStart.setOff([.roughNote], for: file.course.id)
        #expect(starting([file], s, at: at(2, 10, 30)) == nil)
    }

    @Test func theRecordingKeepsItsOwnTime() throws {
        let file = course()
        let early = settings {
            $0.recording = .start; $0.recordingOffsetMinutes = -5
        }
        #expect(starting([file], early, at: at(2, 10, 24)) == nil)
        let c = try #require(starting([file], early, at: at(2, 10, 25)))
        #expect(c.start == at(2, 10, 30))
        #expect(ClassStart.due(c, settings: early.classStart, now: at(2, 10, 25)) == [.recording])
        #expect(ClassStart.due(c, settings: early.classStart, now: at(2, 10, 30)) == [.open, .recording])

        let late = settings {
            $0.recording = .ask; $0.recordingOffsetMinutes = 10
        }
        #expect(ClassStart.due(c, settings: late.classStart, now: at(2, 10, 30)) == [.open])
        #expect(ClassStart.due(c, settings: late.classStart, now: at(2, 10, 40)) == [.open, .recording])

        var banned = early
        banned.classStart.roughNote = .openExisting
        banned.classStart.setOff([.recording], for: file.course.id)
        #expect(starting([file], banned, at: at(2, 10, 25)) == nil)
        #expect(ClassStart.due(c, settings: banned.classStart, now: at(2, 10, 30)) == [.open])
    }

    @Test func aSavedSessionStandsForItsClass() throws {
        var file = course()
        let s = settings()
        let planned = try #require(starting([file], s, at: at(2, 10, 40)))
        let session = Session(device: device, at: at(2, 10, 40), week: 10, date: at(2, 10, 30))
        file.sessions = [session]
        let saved = try #require(starting([file], s, at: at(2, 10, 40)))
        #expect(saved.sessionId == session.id && saved.end == at(2, 11, 45))
        #expect(saved.key == planned.key)

        file.sessions[0].isCancelled = true
        #expect(starting([file], s, at: at(2, 10, 40)) == nil)
    }

    @Test func aSessionWithoutATimeNeverStarts() {
        var file = course(weekday: 3)
        file.sessions = [Session(device: device, at: at(1, 9), week: 10, date: at(4, 0))]
        #expect(starting([file], settings(), at: at(4, 0, 10)) == nil)
    }

    @Test func ofOverlappingClassesTheLaterStartWins() throws {
        var first = course("선형대수학", start: 9 * 60, end: 10 * 60 + 45)
        let second = course()
        let s = settings()

        #expect(try #require(starting([first, second], s, at: at(2, 10, 20))).courseId == first.course.id)
        #expect(try #require(starting([first, second], s, at: at(2, 10, 35))).courseId == second.course.id)

        first.course.schedule = []
        var makeup = Session(device: device, at: at(1, 9), week: 10, date: at(2, 10, 30))
        makeup.kind = .makeup
        makeup.end = at(2, 12)
        first.sessions = [makeup]
        #expect(starting([first, second], s, at: at(2, 10, 35)) == nil)

        var off = s
        off.classStart.setOff(Set(ClassStartSettings.Item.allCases), for: first.course.id)
        #expect(try #require(starting([first, second], off, at: at(2, 10, 35))).courseId == second.course.id)
    }

    @Test func classesAcrossMidnightAndTheDayBoundary() throws {
        let dawn = course(weekday: 2, start: 3 * 60 + 30, end: 4 * 60 + 30)
        let s = settings()
        let before = try #require(starting([dawn], s, at: at(3, 3, 59)))
        let after = try #require(starting([dawn], s, at: at(3, 4, 1)))
        #expect(before == after && before.start == at(3, 3, 30))

        var night = course(weekday: 7)
        night.course.schedule = []
        var makeup = Session(device: device, at: at(1, 9), week: 10, date: at(2, 23, 30))
        makeup.end = at(3, 0, 45)
        night.sessions = [makeup]
        #expect(try #require(starting([night], s, at: at(3, 0, 10))).sessionId == makeup.id)
        #expect(starting([night], s, at: at(3, 0, 45)) == nil)

        let late = course(weekday: 2, start: 30, end: 90)
        #expect(try #require(starting([late], s, at: at(3, 0, 40))).start == at(3, 0, 30))
    }

    @Test func noClassInAnExamWeek() {
        let file = course()
        // 9/1에 시작하는 가을학기의 8주차(10/19부터 10/25까지)는 중간고사 주다.
        let term = Semester(
            device: device, at: at(1, 9), year: 2026, term: .fall, start: LocalDate("2026-09-01"), end: LocalDate("2026-12-20"))
        let s = settings()
        let examMonday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 10, minute: 40))!
        #expect(starting([file], s, at: examMonday, term: term) == nil)
        #expect(starting([file], s, at: at(2, 10, 40), term: term) != nil)
    }

    @Test func aRecordingStopsAfterTheEndOnlyWhenSet() throws {
        let c = StartingClass(courseId: UUID(), sessionId: nil, start: at(2, 10, 30), end: at(2, 11, 45))
        var s = ClassStartSettings()
        #expect(ClassStart.recordingStop(c, settings: s) == nil)
        s.stopsRecording = true
        s.stopAfterMinutes = 5
        #expect(ClassStart.recordingStop(c, settings: s) == at(2, 11, 50))

        s.stopAfterMinutes = -10
        #expect(ClassStart.recordingStop(c, settings: s) == at(2, 11, 35))
        s.recordingOffsetMinutes = 60
        s.stopAfterMinutes = -60
        #expect(ClassStart.recordingStop(c, settings: s) == at(2, 11, 30))
    }

    @Test func theNextClassIsTheOneUnderWayOrNextToStart() {
        var file = course()
        file.sessions = [Session(device: device, at: at(1, 9), week: 10, date: at(2, 10, 30))]
        let s = Settings()
        #expect(
            ClassStart.next([ClassStart.Course(file: file, term: nil)], settings: s, now: at(2, 9), calendar: calendar)?.start
                == at(2, 10, 30))
        #expect(
            ClassStart.next([ClassStart.Course(file: file, term: nil)], settings: s, now: at(2, 11), calendar: calendar)?.start
                == at(2, 10, 30))
    }

    @Test func theLinkedLecturesFromWhereTheLastClassStopped() throws {
        var file = course()
        file.materials = ["Lectures/06_Flows.pdf", "Lectures/05_Matchings.pdf", "Textbooks/West.pdf"].map {
            Material(device: device, at: at(1, 9), path: $0, role: MaterialRole(path: $0), status: .classified)
        }
        let (flows, matchings, book) = (file.materials[0].id, file.materials[1].id, file.materials[2].id)
        file.sessions = [
            Session(device: device, at: at(1, 9), week: 9, date: at(2, 10, 30) - 7 * 86_400),
            Session(device: device, at: at(1, 9), week: 10, date: at(2, 10, 30)),
        ]
        let (last, now) = (file.sessions[0], file.sessions[1])
        file.linkMaterial(matchings, session: last.id, firstPage: 1, lastPage: 12)
        var unit = Unit(device: device, at: at(1, 9), title: "흐름", order: 0)
        unit.sessionIds = [now.id]
        file.units = [unit]
        file.materials[0].unitIds = [unit.id]
        file.linkMaterial(matchings, session: now.id)
        file.linkMaterial(book, session: now.id)
        let session = try #require(file.sessions.first { $0.id == now.id })

        let first = file.startingLectures(for: session, all: false, resumes: true)
        #expect(first.map(\.material) == [matchings] && first.map(\.page) == [13])
        let all = file.startingLectures(for: session, all: true, resumes: false)
        #expect(all.map(\.material) == [matchings, flows] && all.allSatisfy { $0.page == nil })
    }

    @Test func settingsFromBeforeTheSectionReadAsOff() throws {
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"dayBoundaryMinutes": 240}"#.utf8))
        #expect(old.classStart == ClassStartSettings())
        #expect(!old.classStart.isOn(for: UUID()))

        var s = ClassStartSettings()
        s.recording = .start
        let id = UUID()
        s.setOff([.lecture, .recording], for: id)
        #expect(s.courseOff[id.uuidString] == [.recording, .lecture])
        #expect(!s.isOn(.recording, course: id) && s.isOn(.recording, course: UUID()))
        let back = try JSONDecoder().decode(ClassStartSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        s.setOff([], for: id)
        #expect(s.courseOff.isEmpty)
    }

    @Test func pagesOpenInASplitTabUnlessToldOtherwise() throws {
        let old = try JSONDecoder().decode(ClassStartSettings.self, from: Data(#"{"lecture": "open"}"#.utf8))
        #expect(old.openIn == .splitTab)
        var s = Settings()
        s.classStart.openIn = .currentTab
        let data = try JSONEncoder().encode(s)
        #expect(String(decoding: data, as: UTF8.self).contains(#""openIn":"currentTab""#))
        #expect(try JSONDecoder().decode(Settings.self, from: data).classStart.openIn == .currentTab)
    }
}

struct ClassStartPropertyTests {
    let device = UUID()
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    let monday = Date(timeIntervalSince1970: 1_793_545_200)  // 2026-11-02 00:00 KST이다.

    static let startMinute = Gen.int(in: 0...(22 * 60))
    static let length = Gen.int(in: 30...180)
    static let minute = Gen.int(in: 0...(3 * 24 * 60))
    static let offset = Gen.int(in: -30...30)

    func file(start: Int, length: Int) -> CourseFile {
        var file = CourseFile(course: Course(device: device, at: monday, title: "그래프 이론"))
        file.course.schedule = (1...7).map { ClassTime(weekday: $0, startMinute: start, endMinute: start + length) }
        return file
    }

    @Test func aClassStartsOnlyWithinItsTime() async {
        await propertyCheck(input: Self.startMinute, Self.length, Self.minute, Self.offset) { start, length, minute, offset in
            var settings = Settings()
            settings.classStart.recording = .start
            settings.classStart.recordingOffsetMinutes = offset
            let now = monday.addingTimeInterval(Double(minute * 60))
            let course = ClassStart.Course(file: file(start: start, length: length), term: nil)
            guard let c = ClassStart.starting([course], settings: settings, now: now, calendar: calendar) else { return }
            #expect(c.start.addingTimeInterval(Double(min(0, offset) * 60)) <= now && now < c.end)
            #expect(c.end.timeIntervalSince(c.start) == Double(length * 60))
            #expect(!ClassStart.due(c, settings: settings.classStart, now: now).isEmpty)
        }
    }

    @Test func theDayBoundaryNeverChangesTheClass() async {
        await propertyCheck(input: Self.startMinute, Self.length, Self.minute, Gen.int(in: 0...(8 * 60))) {
            start, length, minute, boundary in
            var a = Settings()
            a.classStart.lecture = .open
            var b = a
            b.dayBoundaryMinutes = boundary
            let now = monday.addingTimeInterval(Double(minute * 60))
            let courses = [ClassStart.Course(file: file(start: start, length: length), term: nil)]
            #expect(
                ClassStart.starting(courses, settings: a, now: now, calendar: calendar)
                    == ClassStart.starting(courses, settings: b, now: now, calendar: calendar))
        }
    }

    @Test func aStepDueStaysDue() async {
        await propertyCheck(input: Self.length, Self.offset, Gen.int(in: -40...200), Gen.int(in: 0...200)) { length, offset, first, later in
            var settings = ClassStartSettings()
            settings.recording = .start
            settings.recordingOffsetMinutes = offset
            let start = monday.addingTimeInterval(10 * 3_600)
            let c = StartingClass(courseId: UUID(), sessionId: nil, start: start, end: start.addingTimeInterval(Double(length * 60)))
            let (t1, t2) = (start.addingTimeInterval(Double(first * 60)), start.addingTimeInterval(Double((first + later) * 60)))
            let (d1, d2) = (ClassStart.due(c, settings: settings, now: t1), ClassStart.due(c, settings: settings, now: t2))
            #expect(t2 >= c.end ? d2.isEmpty : d1.isSubset(of: d2))
        }
    }
}
