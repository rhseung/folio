import FolioDomain
import Foundation
import Testing

struct LMSDifferenceTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_793_149_200)
    let room = LMSClassroom(id: 1, title: "그래프 이론[01]")

    func added(_ lms: Int, due: Date? = nil, status: AssignmentStatus = .todo) -> Assignment {
        var a = Assignment(device: device, at: now, title: "HW\(lms)", due: due, source: .lms)
        a.lmsId = lms
        a.status = status
        return a
    }

    func inbox(_ assignments: [LMSAssignment], folio: [Assignment], settings: LMSSettings = LMSSettings(known: [1])) -> (
        LMSInbox, CourseFile
    ) {
        let file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"), assignments: folio)
        let snapshot = LMSSnapshot(at: now, classrooms: [room], assignments: assignments)
        return (LMSInbox.build(snapshot, settings: settings, courses: [file], now: now), file)
    }

    @Test func submittedInTheLMSButOpenInFolioIsProposedAsSubmitted() throws {
        let day = now.addingTimeInterval(86_400)
        let (inbox, file) = inbox(
            [
                .init(id: 1, classroom: 1, title: "HW1", due: day, submitted: true),
                .init(id: 2, classroom: 1, title: "HW2", due: day, submitted: true),
                .init(id: 3, classroom: 1, title: "HW3", due: day),
            ],
            folio: [added(1, due: day), added(2, due: day, status: .submitted), added(3, due: day)])
        #expect(inbox.proposals.map(\.id) == ["submitted:1"])
        let p = inbox.proposals[0].proposal()
        #expect(p.kind == .lmsSubmitted && p.kind.group == .differs && !p.kind.picksCourse)
        #expect(p.action?.command == "assignment status")
        #expect(p.action?.input["course"] == .string(file.course.id.uuidString))
        #expect(p.action?.input["assignment"] == .string(file.assignments[0].id.uuidString))
        #expect(p.action?.input["status"] == "submitted")
        #expect(p.dismissal?.input["keys"] == ["submitted:1"])
    }

    @Test func aChangedDeadlineIsProposedUntilItPasses() {
        let old = now.addingTimeInterval(86_400)
        let new = now.addingTimeInterval(3 * 86_400)
        let (inbox, _) = inbox(
            [
                .init(id: 1, classroom: 1, title: "moved", due: new),
                .init(id: 2, classroom: 1, title: "same", due: old.addingTimeInterval(30)),
                .init(id: 3, classroom: 1, title: "past", due: now.addingTimeInterval(-60)),
                .init(id: 4, classroom: 1, title: "no deadline in Folio", due: new),
            ],
            folio: [added(1, due: old), added(2, due: old), added(3, due: old), added(4)])
        let stamp = Int(new.timeIntervalSince1970 / 60)
        #expect(inbox.proposals.map(\.id) == ["due:1:\(stamp)", "due:4:\(stamp)"])
        let p = inbox.proposals[0].proposal()
        #expect(p.kind == .lmsDue)
        #expect(p.action?.command == "assignment set")
        guard case .string(let text)? = p.action?.input["due"] else { Issue.record("no due"); return }
        #expect(abs((try? Date(text, strategy: .iso8601))?.timeIntervalSince(new) ?? 99) < 1)
    }

    @Test func aDismissedDeadlineComesBackWhenItMovesAgain() {
        let old = now.addingTimeInterval(86_400)
        let first = now.addingTimeInterval(2 * 86_400)
        var settings = LMSSettings(known: [1])
        settings.mark([LMSKey(kind: .due, id: 1, stamp: Int(first.timeIntervalSince1970 / 60))], handled: true)
        let (quiet, _) = inbox([.init(id: 1, classroom: 1, title: "HW1", due: first)], folio: [added(1, due: old)], settings: settings)
        #expect(quiet.proposals.isEmpty)
        #expect(quiet.sections[0].handled.map(\.id).contains("due:\(1):\(Int(first.timeIntervalSince1970 / 60))"))
        let again = now.addingTimeInterval(4 * 86_400)
        let (back, _) = inbox([.init(id: 1, classroom: 1, title: "HW1", due: again)], folio: [added(1, due: old)], settings: settings)
        #expect(back.proposals.map(\.id) == ["due:1:\(Int(again.timeIntervalSince1970 / 60))"])
    }

    @Test func repeatingAssignmentsKeepTheirOwnDeadlines() {
        var weekly = added(1, due: now.addingTimeInterval(86_400))
        weekly.repeats = .weekly
        let (inbox, _) = inbox([.init(id: 1, classroom: 1, title: "SP", due: now.addingTimeInterval(2 * 86_400))], folio: [weekly])
        #expect(inbox.proposals.isEmpty)
    }

    @Test func thisWeeksDeadlinesShowReceivedAndNewAssignments() {
        let (inbox, file) = inbox(
            [
                .init(id: 1, classroom: 1, title: "received", due: now.addingTimeInterval(86_400)),
                .init(id: 2, classroom: 1, title: "new", due: now.addingTimeInterval(2 * 86_400)),
                .init(id: 3, classroom: 1, title: "next month", due: now.addingTimeInterval(30 * 86_400)),
                .init(id: 4, classroom: 1, title: "handed in", due: now.addingTimeInterval(86_400), submitted: true),
                .init(id: 5, classroom: 1, title: "past", due: now.addingTimeInterval(-60)),
            ],
            folio: [added(1, due: now.addingTimeInterval(86_400))])
        let deadlines = inbox.sections[0].deadlines
        #expect(deadlines.map(\.id) == [1, 2])
        #expect(deadlines.map(\.course) == [file.course.id, nil])
        let board = ProposalBoard.build(lms: inbox)
        #expect(board.deadlines.map(\.id) == [1, 2])
    }

    @Test func keysCarryTheDismissedDeadline() {
        #expect(LMSKey("due:5:29885820") == LMSKey(kind: .due, id: 5, stamp: 29_885_820))
        #expect(LMSKey(kind: .due, id: 5, stamp: 29_885_820).description == "due:5:29885820")
        #expect(LMSKey("submitted:5")?.stamp == nil)
        #expect(LMSKey("due:5:x") == nil)
        #expect(LMSKey(kind: .due, id: 5) < LMSKey(kind: .due, id: 5, stamp: 1))
    }
}

struct LMSRoomMemoryTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_793_149_200)

    @Test func roomsRememberACourseNoCourseOrNothing() throws {
        let course = UUID()
        var s = LMSSettings()
        s.remember(LMSRoom(course: course), for: 27967)
        s.remember(LMSRoom(), for: 28011)
        #expect(s.course(of: 27967) == course)
        #expect(s.room(28011) == LMSRoom() && s.course(of: 28011) == nil)
        #expect(s.room(1) == nil)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any]
        let rooms = json?["rooms"] as? [String: [String: String]]
        #expect(rooms?["27967"]?["course"] == course.uuidString)
        #expect(rooms?["28011"] == [:])
        #expect(try JSONDecoder().decode(LMSSettings.self, from: JSONEncoder().encode(s)) == s)
        s.remember(nil, for: 27967)
        #expect(s.room(27967) == nil)
    }

    @Test func rememberedProposalsAreTheNewItemsOfRoomsWithACourse() {
        let course = UUID()
        var settings = LMSSettings(known: [1, 2, 3])
        settings.remember(LMSRoom(course: course), for: 1)
        settings.remember(LMSRoom(), for: 2)
        let snapshot = LMSSnapshot(
            at: now, classrooms: [.init(id: 1, title: "a"), .init(id: 2, title: "b"), .init(id: 3, title: "c")],
            files: [
                .init(id: 10, classroom: 1, title: "x"), .init(id: 11, classroom: 2, title: "y"), .init(id: 12, classroom: 3, title: "z"),
            ],
            notices: [.init(id: 20, board: 1, classroom: 1, title: "n")])
        let board = ProposalBoard.build(
            lms: LMSInbox.build(snapshot, settings: settings, courses: [], now: now), settings: settings, viewerOnly: [])
        #expect(board.remembered.map(\.id) == ["lms/file:10"])
        #expect(board.room(1)?.course == course)
        #expect(board.room(2)?.memory == LMSRoom())
        let approvals = board.remembered.rememberedApprovals
        #expect(approvals.count == 1 && approvals[0].input["course"] == nil)
        guard case .array(let items)? = approvals[0].input["items"] else { Issue.record("no items"); return }
        #expect(items[0]["classroom"] == .number(1))
        #expect(settings.classrooms(of: course, in: snapshot).map(\.id) == [1])
    }

    @Test func aRememberedCourseThatIsGoneIsNotRemembered() {
        var settings = LMSSettings(known: [1])
        settings.remember(LMSRoom(course: UUID()), for: 1)
        let snapshot = LMSSnapshot(
            at: now, classrooms: [.init(id: 1, title: "a")], files: [.init(id: 10, classroom: 1, title: "x")])
        let board = ProposalBoard.build(
            lms: LMSInbox.build(snapshot, settings: settings, courses: [], now: now), settings: settings, courses: [UUID()])
        #expect(board.remembered.isEmpty)
        #expect(board.room(1)?.memory == nil)
    }
}
