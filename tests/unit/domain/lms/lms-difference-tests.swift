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

    @Test func attachmentsMissingFromTheAssignmentFolderAreProposed() throws {
        let day = now.addingTimeInterval(86_400)
        let hw = LMSAttachment(name: "hw.pdf", path: "/a/hw.pdf"), hint = LMSAttachment(name: "hint.pdf", path: "/a/hint.pdf")
        let a = added(1, due: day)
        var file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"), assignments: [a])
        file.materials = [
            Material(device: device, at: now, path: "\(AssignmentFiles.path(of: a))/hw.pdf", kind: .problem, status: .classified),
            Material(device: device, at: now, path: "Lectures/hint.pdf", status: .classified),
        ]
        func build(_ attachments: [LMSAttachment]?, settings: LMSSettings = LMSSettings(known: [1])) -> LMSInbox {
            let lms = LMSAssignment(id: 1, classroom: 1, title: "HW1", due: day, attachments: attachments)
            return LMSInbox.build(
                LMSSnapshot(at: now, classrooms: [room], assignments: [lms]), settings: settings, courses: [file], now: now)
        }
        #expect(build(nil).proposals.isEmpty)
        #expect(build([hw]).proposals.isEmpty)
        let inbox = build([hw, hint])
        #expect(inbox.proposals.map(\.id) == ["attachments:1:2"])
        #expect(inbox.proposals[0].attachments == [hint])
        let p = inbox.proposals[0].proposal()
        #expect(p.kind == .lmsAttachments && p.kind.group == .differs && !p.kind.picksCourse)
        #expect(p.action?.command == "lms accept")
        #expect(p.action?.input["course"] == .string(file.course.id.uuidString))
        #expect(p.downloaded(files: ["/tmp/hint.pdf"]).action?.input["items"] == [["key": "attachments:1:2", "files": ["/tmp/hint.pdf"]]])

        var dismissed = LMSSettings(known: [1])
        dismissed.mark([inbox.proposals[0].key], handled: true)
        #expect(build([hw, hint], settings: dismissed).proposals.isEmpty)
        let more = LMSAttachment(name: "more.pdf", path: "/a/more.pdf")
        #expect(build([hw, hint, more], settings: dismissed).proposals.map(\.id) == ["attachments:1:3"])
    }

    @Test func attachmentsAreReadForReceivedAssignmentsStillToDo() {
        let day = now.addingTimeInterval(86_400)
        let snapshot = LMSSnapshot(
            at: now, classrooms: [room],
            assignments: [
                .init(id: 1, classroom: 1, title: "HW1", due: day), .init(id: 2, classroom: 1, title: "HW2", due: day),
                .init(id: 3, classroom: 1, title: "HW3", due: now.addingTimeInterval(-60)),
            ])
        let file = CourseFile(
            course: Course(device: device, at: now, title: "그래프 이론"),
            assignments: [added(1, due: day), added(2, due: day, status: .submitted), added(3)])
        let read = LMSInbox.pagesToRead(snapshot, settings: LMSSettings(known: [1]), courses: [file], now: now)
        #expect(read.map(\.id) == [1])
    }

    @Test func submittedInTheLMSIsMarkedWithoutAskingOnce() throws {
        let day = now.addingTimeInterval(86_400)
        let at = now.addingTimeInterval(-3_600)
        let assignments: [LMSAssignment] = [
            .init(id: 1, classroom: 1, title: "HW1", due: day, submitted: true, submittedAt: at),
            .init(id: 2, classroom: 1, title: "HW2", due: day, submitted: true),
            .init(id: 3, classroom: 1, title: "HW3", due: day),
        ]
        let (inbox, file) = inbox(assignments, folio: [added(1, due: day), added(2, due: day, status: .submitted), added(3, due: day)])
        // 묻지 않고 바꾸므로 제안에는 없다.
        #expect(inbox.proposals.isEmpty)
        let snapshot = LMSSnapshot(at: now, classrooms: [room], assignments: assignments)
        let found = LMSInbox.submissions(snapshot, settings: LMSSettings(known: [1]), courses: [file])
        #expect(found == [LMSSubmission(course: file.course.id, assignment: file.assignments[0].id, lms: 1, at: at)])
        #expect(found[0].key.description == "submitted:1")
        // 한 번 바꾼 과제는 사용자가 할 일로 되돌려도 또 바꾸지 않는다.
        var settings = LMSSettings(known: [1])
        settings.mark([found[0].key], handled: true)
        #expect(LMSInbox.submissions(snapshot, settings: settings, courses: [file]).isEmpty)
    }

    @Test func submittedInFolioButNotInTheLMSAfterTheDeadlineIsAWarning() {
        let past = now.addingTimeInterval(-60)
        let (inbox, _) = inbox(
            [
                .init(id: 1, classroom: 1, title: "HW1", due: past),
                .init(id: 2, classroom: 1, title: "HW2", due: now.addingTimeInterval(86_400)),
                .init(id: 3, classroom: 1, title: "HW3", due: past, submitted: true),
            ],
            folio: [
                added(1, due: past, status: .submitted), added(2, due: now.addingTimeInterval(86_400), status: .submitted),
                added(3, due: past, status: .submitted),
            ])
        #expect(inbox.proposals.map(\.id) == ["unsubmitted:1"])
        let p = inbox.proposals[0].proposal()
        #expect(p.kind == .lmsUnsubmitted && p.kind.group == .differs && !p.kind.picksCourse)
        #expect(p.action == nil)
        #expect(p.dismissal?.input["keys"] == ["unsubmitted:1"])
    }

    @Test func pastTheLMSDeadlineButNotSubmittedThereIsOverdue() {
        let past = now.addingTimeInterval(-60)
        let snapshot = LMSSnapshot(
            at: now, classrooms: [room],
            assignments: [
                .init(id: 1, classroom: 1, title: "HW1", due: past), .init(id: 2, classroom: 1, title: "HW2", due: past),
                .init(id: 3, classroom: 1, title: "HW3", due: past), .init(id: 4, classroom: 1, title: "HW4", due: past),
                .init(id: 5, classroom: 1, title: "HW5", due: past, submitted: true),
                .init(id: 6, classroom: 1, title: "HW6", due: now.addingTimeInterval(60)),
            ])
        // Folio의 마감이 아니라 LMS의 마감으로 센다. 4는 못 냄, 5는 LMS에서 냈고 6은 마감 전이다.
        let file = CourseFile(
            course: Course(device: device, at: now, title: "그래프 이론"),
            assignments: [
                added(1, due: now.addingTimeInterval(86_400)), added(2, status: .submitted), added(3, status: .graded),
                added(4, status: .missed), added(5), added(6),
            ])
        let found = LMSInbox.unsubmitted(snapshot, in: file, now: now)
        #expect(Set(found.keys) == [file.assignments[0].id, file.assignments[1].id])
        #expect(found[file.assignments[0].id]?.id == 1)
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
