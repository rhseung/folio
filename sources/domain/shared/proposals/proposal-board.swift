import Foundation

// LMS 탭이 그리는 값이다. 열의 행(전체, 강의실, 대화)과 행마다의 제안을 정한다.
public struct ProposalBoard: Sendable, Equatable {
    public struct Room: Sendable, Equatable, Identifiable {
        public var classroom: LMSClassroom
        public var proposals: [Proposal]
        public var hidden: [LMSInbox.Handled]
        public var id: Int { classroom.id }
    }

    public struct Thread: Sendable, Equatable, Identifiable {
        public var course: UUID
        public var chat: UUID
        public var title: String
        public var proposals: [Proposal]
        public var id: UUID { chat }
    }

    public struct Group: Sendable, Equatable, Identifiable {
        public var group: ProposalGroup
        public var proposals: [Proposal]
        public var id: ProposalGroup { group }
    }

    public var rooms: [Room]
    public var threads: [Thread]

    public init(rooms: [Room] = [], threads: [Thread] = []) {
        self.rooms = rooms
        self.threads = threads
    }

    public struct CourseChat: Sendable {
        public var course: UUID
        public var chat: Chat

        public init(course: UUID, chat: Chat) {
            self.course = course
            self.chat = chat
        }
    }

    // 대화는 기다리는 제안이 있는 것만 열에 선다. 대화마다 행을 두면 끝난 대화가 열을 채운다. 강의실은 숨긴 항목만
    // 남아도 서서 "다시 제안"으로 되돌릴 수 있다(`LMSInbox.build`).
    public static func build(
        lms: LMSInbox, viewerOnly: Set<Int> = [], chats: [CourseChat], targets: [String: ProposalTarget]
    ) -> ProposalBoard {
        let rooms = lms.sections.map { s in
            Room(
                classroom: s.classroom,
                proposals: s.proposals.map { p in p.proposal(viewerOnly: p.fileID.map(viewerOnly.contains) ?? false) },
                hidden: s.handled)
        }
        let threads = chats.sorted { $0.chat.updatedAt > $1.chat.updatedAt }.compactMap { c -> Thread? in
            let pending = c.chat.pending(course: c.course, targets: targets)
            return pending.isEmpty ? nil : Thread(course: c.course, chat: c.chat.id, title: c.chat.title, proposals: pending)
        }
        return ProposalBoard(rooms: rooms, threads: threads)
    }

    public var proposals: [Proposal] { rooms.flatMap(\.proposals) + threads.flatMap(\.proposals) }
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

    public func room(_ id: Int) -> Room? { rooms.first { $0.id == id } }
    public func thread(_ id: UUID) -> Thread? { threads.first { $0.id == id } }
}
