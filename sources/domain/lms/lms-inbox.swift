import Foundation

public struct LMSInbox: Sendable, Equatable {
    public struct Handled: Sendable, Equatable, Identifiable {
        public var proposal: LMSProposal
        public var course: UUID?
        // 과목에 이미 있거나, 제출했거나, 마감이 지난 과제는 `build`가 제안에서 빼므로, 표시를 거두면 화면에서 아예
        // 사라진다. 그래서 이런 과제는 false이다.
        public var proposable: Bool
        public var id: String { proposal.id }
    }

    public struct Section: Sendable, Equatable, Identifiable {
        public var classroom: LMSClassroom
        public var proposals: [LMSProposal]
        public var handled: [Handled]
        public var deadlines: [LMSDeadline]
        public var id: Int { classroom.id }

        public init(classroom: LMSClassroom, proposals: [LMSProposal], handled: [Handled] = [], deadlines: [LMSDeadline] = []) {
            self.classroom = classroom
            self.proposals = proposals
            self.handled = handled
            self.deadlines = deadlines
        }
    }

    public var sections: [Section]

    public init(sections: [Section] = []) { self.sections = sections }

    public var proposals: [LMSProposal] { sections.flatMap(\.proposals) }
    public var waiting: [Section] { sections.filter { !$0.proposals.isEmpty } }
    public var isEmpty: Bool { proposals.isEmpty }

    // "이번 주 기한"은 과제의 "곧 마감" 일수(`urgency.assignmentSoonDays`) 안에 마감이 오는 LMS 과제다. 오늘 화면의 마감 칩과
    // 같은 값을 써야 두 화면이 같은 과제를 곧 마감으로 본다.
    public static func build(
        _ snapshot: LMSSnapshot, settings: LMSSettings, courses: [CourseFile], now: Date,
        soonDays: Int = SettingItem.assignmentSoonDays.int
    ) -> LMSInbox {
        let window = TimeInterval(soonDays * 24 * 60 * 60)
        let known = Set(settings.known)
        let handledKeys = Set(settings.handled)
        var addedTo: [Int: (course: UUID, assignment: Assignment)] = [:]
        for course in courses { for a in course.assignments { if let id = a.lmsId { addedTo[id] = (course.course.id, a) } } }
        var open: [Int: [LMSProposal.Item]] = [:]
        var done: [Int: [(item: LMSProposal.Item, course: UUID?, proposable: Bool)]] = [:]
        var deadlines: [Int: [(LMSAssignment, UUID?)]] = [:]
        for a in snapshot.assignments {
            let doable = !a.submitted && (a.due.map { $0 >= now } ?? true)
            if let due = a.due, doable, due.timeIntervalSince(now) <= window {
                deadlines[a.classroom, default: []].append((a, addedTo[a.id]?.course))
            }
            if let added = addedTo[a.id] {
                done[a.classroom, default: []].append((.assignment(a), added.course, false))
                for d in LMSDifference.find(a, in: added.assignment, course: added.course, now: now) {
                    if handledKeys.contains(d.key) {
                        done[a.classroom, default: []].append((.difference(d), added.course, true))
                    } else {
                        open[a.classroom, default: []].append(.difference(d))
                    }
                }
            } else if handledKeys.contains(a.key) {
                done[a.classroom, default: []].append((.assignment(a), nil, doable))
            } else if doable {
                open[a.classroom, default: []].append(.assignment(a))
            }
        }
        for f in snapshot.files {
            if handledKeys.contains(f.key) {
                done[f.classroom, default: []].append((.file(f), nil, true))
            } else {
                open[f.classroom, default: []].append(.file(f))
            }
        }
        for n in snapshot.notices {
            if handledKeys.contains(n.key) {
                done[n.classroom, default: []].append((.notice(n), nil, true))
            } else {
                open[n.classroom, default: []].append(.notice(n))
            }
        }
        let sections = snapshot.classrooms.compactMap { room -> Section? in
            guard known.contains(room.id) else { return nil }
            let proposals = (open[room.id] ?? []).map { LMSProposal(item: $0, classroom: room) }
            let handled = (done[room.id] ?? []).map {
                Handled(proposal: LMSProposal(item: $0.item, classroom: room), course: $0.course, proposable: $0.proposable)
            }
            let due = (deadlines[room.id] ?? []).map { LMSDeadline(assignment: $0.0, classroom: room, course: $0.1) }
            return proposals.isEmpty && handled.isEmpty && due.isEmpty
                ? nil : Section(classroom: room, proposals: proposals, handled: handled, deadlines: due)
        }
        return LMSInbox(sections: sections.filter { !$0.proposals.isEmpty } + sections.filter { $0.proposals.isEmpty })
    }

    // 동기화가 첨부를 읽으러 과제 페이지를 하나 더 여는 과제다. 요청을 아끼려고 지금 제안할 과제만 고른다. 처음 보는 강의실은
    // 동기화 직후 `lms seen`으로 기록되고 그 과제도 곧 제안되므로 함께 센다.
    public static func attachmentsToRead(
        _ snapshot: LMSSnapshot, settings: LMSSettings, courses: [CourseFile], now: Date
    ) -> [LMSAssignment] {
        var settings = settings
        settings.know(snapshot.classrooms.map(\.id))
        return build(snapshot, settings: settings, courses: courses, now: now).proposals.compactMap {
            if case .assignment(let a) = $0.item { a } else { nil }
        }
    }
}
