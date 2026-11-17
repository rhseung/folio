import FolioCore
import Foundation

public struct LMSProposal: Hashable, Sendable, Identifiable {
    public enum Item: Hashable, Sendable {
        case assignment(LMSAssignment)
        case file(LMSFile)
        case notice(LMSNotice)
        case difference(LMSDifference)
    }

    public var item: Item
    public var classroom: LMSClassroom

    public init(item: Item, classroom: LMSClassroom) {
        self.item = item
        self.classroom = classroom
    }

    public var key: LMSKey {
        switch item {
        case .assignment(let a): a.key
        case .file(let f): f.key
        case .notice(let n): n.key
        case .difference(let d): d.key
        }
    }

    public var id: String { key.description }

    public var title: String {
        switch item {
        case .assignment(let a): a.title
        case .file(let f): f.title
        case .notice(let n): n.title
        case .difference(let d): d.lms.title
        }
    }

    public var url: URL {
        switch item {
        case .assignment(let a): a.url
        case .file(let f): f.url
        case .notice(let n): n.url
        case .difference(let d): d.lms.url
        }
    }

    var fileID: Int? {
        if case .file(let f) = item { return f.id }
        return nil
    }

    // 받을 때 내려받을 첨부다. 받은 과제의 새 첨부는 과제 폴더에 없는 것만이다.
    public var attachments: [LMSAttachment] {
        switch item {
        case .assignment(let a): a.attachments ?? []
        case .difference(let d): if case .attachments(let new) = d.change { new } else { [] }
        case .file, .notice: []
        }
    }
}

extension LMSProposal {
    public var kind: ProposalKind {
        switch item {
        case .assignment: .lmsAssignment
        case .file: .lmsFile
        case .notice: .lmsNotice
        case .difference(let d):
            switch d.change {
            case .unsubmitted: .lmsUnsubmitted
            case .due: .lmsDue
            case .attachments: .lmsAttachments
            }
        }
    }

    // 받기(`lms accept`)의 항목에는 내려받은 파일이 없다. 파일은 승인한 기기가 받아 `file`과 `files`에 넣는다.
    public func proposal(viewerOnly: Bool = false) -> Proposal {
        let dismissal = ActionProposal(command: "lms mark", input: ["keys": [.string(key.description)]])
        if case .difference(let d) = item {
            return Proposal(kind: kind, source: .lms(self), action: d.action, dismissal: dismissal)
        }
        // 강의실을 적어 두면 `lms accept`가 받은 과목을 그 강의실에 기억하고, 과목 없이 받으면 기억한 과목에 넣는다.
        var item: [String: JSONValue] = ["key": .string(key.description), "classroom": .number(Double(classroom.id))]
        if case .assignment(let a) = self.item {
            item["title"] = .string(a.title)
            if let due = a.due { item["due"] = .string(Self.date(due)) }
            if let n = a.attachments?.count, n > 0 { item["attachmentCount"] = .number(Double(n)) }
        }
        let accept = ActionProposal(command: "lms accept", input: ["items": [.object(item)]])
        return Proposal(
            kind: kind, source: .lms(self), action: kind.picksCourse ? accept : nil, dismissal: dismissal,
            flag: viewerOnly ? .viewerOnly : nil)
    }

    // storage의 JSONFormat이 읽는 날짜 꼴이다.
    static func date(_ date: Date) -> String { date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)) }
}

extension LMSDifference {
    // LMS 미제출은 Folio가 고칠 수 없어 LMS에서 열기와 무시만 둔다.
    var action: ActionProposal? {
        var input: [String: JSONValue] = ["course": .string(course.uuidString), "assignment": .string(assignment.uuidString)]
        switch change {
        case .unsubmitted:
            return nil
        case .due(_, let date):
            input["due"] = .string(LMSProposal.date(date))
            return ActionProposal(command: "assignment set", input: .object(input))
        case .attachments:
            // 파일은 승인한 기기가 내려받아 `files`에 넣는다(`Proposal.downloaded`).
            let item: [String: JSONValue] = ["key": .string(key.description)]
            return ActionProposal(command: "lms accept", input: ["course": .string(course.uuidString), "items": [.object(item)]])
        }
    }
}

extension Proposal {
    // 승인한 기기가 내려받은 파일을 받기 항목에 넣는다. 자료는 `file` 하나, 과제는 첨부 `files`이다.
    public func downloaded(file: String? = nil, files: [String] = []) -> Proposal {
        guard case .lms = source, var action, case .array(var items)? = action.input["items"], !items.isEmpty else { return self }
        if let file { items[0]["file"] = .string(file) }
        if !files.isEmpty { items[0]["files"] = .array(files.map(JSONValue.string)) }
        action.input["items"] = .array(items)
        var p = self
        p.action = action
        return p
    }
}
