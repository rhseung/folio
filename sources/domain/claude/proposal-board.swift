import Foundation

// LMS 탭이 그리는 값이다. 열의 행(전체, 강의실)과 행마다의 제안을 정한다.
public struct ProposalBoard: Sendable, Equatable {
    public struct Room: Sendable, Equatable, Identifiable {
        public var classroom: LMSClassroom
        public var proposals: [Proposal]
        public var hidden: [LMSInbox.Handled]
        public var deadlines: [LMSDeadline]
        // 받을 때 고른 과목의 기억이다(`LMSSettings.rooms`). nil이면 기억이 없다.
        public var memory: LMSRoom?
        public var id: Int { classroom.id }

        public init(
            classroom: LMSClassroom, proposals: [Proposal], hidden: [LMSInbox.Handled] = [], deadlines: [LMSDeadline] = [],
            memory: LMSRoom? = nil
        ) {
            self.classroom = classroom
            self.proposals = proposals
            self.hidden = hidden
            self.deadlines = deadlines
            self.memory = memory
        }

        public var course: UUID? { memory?.course }

        // 기억한 과목에 바로 받을 수 있는 새 항목이다. 고칠 것(Folio와 다른 것)은 하나씩 처리하므로 넣지 않는다.
        public var remembered: [Proposal] {
            guard course != nil else { return [] }
            return proposals.filter { $0.kind.picksCourse && $0.canApprove }
        }
    }

    public struct Group: Sendable, Equatable, Identifiable {
        public var group: ProposalGroup
        public var proposals: [Proposal]
        public var id: ProposalGroup { group }
    }

    public var rooms: [Room]

    public init(rooms: [Room] = []) { self.rooms = rooms }

    // 강의실은 숨긴 항목만 남아도 서서 "다시 제안"으로 되돌릴 수 있다(`LMSInbox.build`).
    public static func build(lms: LMSInbox, settings: LMSSettings = .init(), viewerOnly: Set<Int> = []) -> ProposalBoard {
        ProposalBoard(
            rooms: lms.sections.map { s in
                Room(
                    classroom: s.classroom,
                    proposals: s.proposals.map { p in p.proposal(viewerOnly: p.fileID.map(viewerOnly.contains) ?? false) },
                    hidden: s.handled, deadlines: s.deadlines, memory: settings.room(s.classroom.id))
            })
    }

    public var proposals: [Proposal] { rooms.flatMap(\.proposals) }
    public var count: Int { proposals.count }
    public var isEmpty: Bool { proposals.isEmpty }

    // "전체"는 무리마다 모으고 빈 무리는 뺀다.
    public var groups: [Group] {
        let all = proposals
        return ProposalGroup.allCases.compactMap { g in
            let mine = all.filter { $0.kind.group == g }
            return mine.isEmpty ? nil : Group(group: g, proposals: mine)
        }
    }

    public var deadlines: [LMSDeadline] {
        rooms.flatMap(\.deadlines).sorted { ($0.assignment.due ?? .distantFuture) < ($1.assignment.due ?? .distantFuture) }
    }

    public var remembered: [Proposal] { rooms.flatMap(\.remembered) }

    public func room(_ id: Int) -> Room? { rooms.first { $0.id == id } }
}
