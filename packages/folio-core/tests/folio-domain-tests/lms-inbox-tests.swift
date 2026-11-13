import FolioDomain
import Foundation
import Testing

struct LMSInboxTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_793_149_200)

    func course(_ title: String, assignments: [Assignment] = []) -> CourseFile {
        CourseFile(course: Course(device: device, at: now, title: title), assignments: assignments)
    }

    /// Sections are the LMS classrooms by their own names, in the dashboard's order, two of one course and one that is
    /// no course alike. A classroom not seen before proposes nothing until the sync marked what it held.
    @Test func sectionsAreKnownClassroomsByTheirOwnNames() {
        let snapshot = LMSSnapshot(
            at: now,
            classrooms: [.init(id: 1, title: "그래프 이론[01]"), .init(id: 2, title: "그래프 이론[02]"), .init(id: 3, title: "소방 안전 교육"),
                         .init(id: 4, title: "선형대수학")],
            files: [.init(id: 10, classroom: 1, title: "a"), .init(id: 11, classroom: 2, title: "b"), .init(id: 12, classroom: 3, title: "c"),
                    .init(id: 13, classroom: 4, title: "d")])
        var settings = LMSSettings()
        settings.know([3, 1, 2])
        let inbox = LMSInbox.build(snapshot, settings: settings, courses: [], now: now)
        #expect(inbox.sections.map(\.classroom.title) == ["그래프 이론[01]", "그래프 이론[02]", "소방 안전 교육"])
        #expect(inbox.proposals.map(\.id) == ["file:10", "file:11", "file:12"])
        #expect(settings.unseen(in: snapshot).map(\.id) == [4])
        #expect(settings.known == [1, 2, 3])
    }

    @Test func assignmentsAreProposedWhileTheyCanStillBeDone() {
        var added = Assignment(device: device, at: now, title: "HW3", source: .lms)
        added.lmsId = 104
        // Added to some course from another classroom's proposal: still not proposed again.
        let other = course("선형대수학", assignments: [added])
        var settings = LMSSettings(known: [1])
        settings.mark([LMSKey(kind: .assignment, id: 105)], handled: true)
        let snapshot = LMSSnapshot(at: now, classrooms: [.init(id: 1, title: "그래프 이론")], assignments: [
            .init(id: 100, classroom: 1, title: "open", due: now.addingTimeInterval(3600)),
            .init(id: 101, classroom: 1, title: "due now", due: now),
            .init(id: 102, classroom: 1, title: "past", due: now.addingTimeInterval(-1)),
            .init(id: 103, classroom: 1, title: "handed in", due: now.addingTimeInterval(3600), submitted: true),
            .init(id: 104, classroom: 1, title: "already added"),
            .init(id: 105, classroom: 1, title: "dismissed"),
            .init(id: 106, classroom: 1, title: "no deadline"),
        ])
        let inbox = LMSInbox.build(snapshot, settings: settings, courses: [course("그래프 이론"), other], now: now)
        #expect(inbox.proposals.map(\.id) == ["assignment:100", "assignment:101", "assignment:106"])
        // The added one says where it went and the dismissed one can come back; a deadline that passed is neither.
        #expect(inbox.sections[0].handled.map(\.id) == ["assignment:104", "assignment:105"])
        #expect(inbox.sections[0].handled.map(\.course) == [other.course.id, nil])
    }

    @Test func handledFilesAndNoticesStayQuiet() {
        let snapshot = LMSSnapshot(at: now, classrooms: [.init(id: 1, title: "그래프 이론"), .init(id: 2, title: "빈 강의실")],
                                   files: [.init(id: 10, classroom: 1, title: "old"), .init(id: 11, classroom: 1, title: "new")],
                                   notices: [.init(id: 20, board: 5, classroom: 1, title: "old"), .init(id: 21, board: 5, classroom: 1, title: "new")])
        var settings = LMSSettings(known: [1, 2])
        settings.mark([LMSKey(kind: .file, id: 10), LMSKey(kind: .notice, id: 20)], handled: true)
        let inbox = LMSInbox.build(snapshot, settings: settings, courses: [], now: now)
        #expect(inbox.proposals.map(\.id) == ["file:11", "notice:21"])
        #expect(inbox.sections[0].handled.map(\.id) == ["file:10", "notice:20"])
        #expect(inbox.sections.map(\.id) == [1])
        #expect(snapshot.current(in: 1) == [LMSKey(kind: .file, id: 10), LMSKey(kind: .file, id: 11), LMSKey(kind: .notice, id: 20), LMSKey(kind: .notice, id: 21)])
    }

    /// Every item of a classroom stays in view, handled ones too, so a dismissal made by mistake can be taken back. Those
    /// with something new come first; one with only handled items follows, and is no count anywhere.
    @Test func classroomsWithOnlyHandledItemsFollowAndCountForNothing() {
        let snapshot = LMSSnapshot(at: now, classrooms: [.init(id: 1, title: "다 본 강의실"), .init(id: 2, title: "새 글"), .init(id: 3, title: "빈 강의실")],
                                   files: [.init(id: 10, classroom: 1, title: "old"), .init(id: 11, classroom: 2, title: "new")])
        var settings = LMSSettings(known: [1, 2, 3])
        settings.mark([LMSKey(kind: .file, id: 10)], handled: true)
        var inbox = LMSInbox.build(snapshot, settings: settings, courses: [], now: now)
        #expect(inbox.sections.map(\.id) == [2, 1])
        #expect(inbox.waiting.map(\.id) == [2])
        #expect(!inbox.isEmpty)
        settings.mark([LMSKey(kind: .file, id: 11)], handled: true)
        inbox = LMSInbox.build(snapshot, settings: settings, courses: [], now: now)
        #expect(inbox.isEmpty && inbox.waiting.isEmpty)
        #expect(inbox.sections.map(\.id) == [1, 2])
        settings.mark([LMSKey(kind: .file, id: 10)], handled: false)
        #expect(LMSInbox.build(snapshot, settings: settings, courses: [], now: now).proposals.map(\.id) == ["file:10"])
    }

    @Test func markAndKnowKeepTheListsSortedAndUnique() {
        var s = LMSSettings()
        s.mark([LMSKey(kind: .notice, id: 2), LMSKey(kind: .file, id: 9), LMSKey(kind: .notice, id: 2)], handled: true)
        s.mark([LMSKey(kind: .file, id: 1)], handled: true)
        #expect(s.handled.map(\.description) == ["file:1", "file:9", "notice:2"])
        s.mark([LMSKey(kind: .file, id: 9)], handled: false)
        #expect(s.handled.map(\.description) == ["file:1", "notice:2"])
        s.know([28011, 27967, 28011])
        s.know([27967])
        #expect(s.known == [27967, 28011])
    }

    @Test func settingsRoundTripAndOldFilesReadEmpty() throws {
        var s = LMSSettings(known: [27967, 28011])
        s.mark([LMSKey(kind: .file, id: 1)], handled: true)
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(LMSSettings.self, from: data) == s)
        #expect(LMSKey("notice:5") == LMSKey(kind: .notice, id: 5))
        #expect(LMSKey("notice") == nil)
        #expect(LMSKey("page:5") == nil)
        let old = try JSONDecoder().decode(Settings.self, from: Data(#"{"schemaVersion":1}"#.utf8))
        #expect(old.lms == LMSSettings())
    }
}

struct LMSFileNameTests {
    @Test func lectureNameTakesTheWeek() {
        let file = LMSFile(id: 1, classroom: 1, title: "Matchings", week: "5주차 [9월28일 - 10월4일]")
        #expect(file.lectureName("Matchings.pdf") == "05_Matchings.pdf")
        #expect(file.lectureName("05_Matchings.pdf") == "05_Matchings.pdf")
        #expect(LMSFile(id: 1, classroom: 1, title: "x", week: "12주차").lectureName("a.pdf") == "12_a.pdf")
        #expect(LMSFile(id: 1, classroom: 1, title: "x", week: "강의 개요").lectureName("a.pdf") == "a.pdf")
        #expect(LMSFile(id: 1, classroom: 1, title: "x").lectureName("a.pdf") == "a.pdf")
    }
}
