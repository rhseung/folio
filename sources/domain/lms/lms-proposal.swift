import FolioCore
import Foundation

public struct LMSProposal: Hashable, Sendable, Identifiable {
    public enum Item: Hashable, Sendable {
        case assignment(LMSAssignment)
        case file(LMSFile)
        case notice(LMSNotice)
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
        }
    }

    public var id: String { key.description }

    public var title: String {
        switch item {
        case .assignment(let a): a.title
        case .file(let f): f.title
        case .notice(let n): n.title
        }
    }

    public var url: URL {
        switch item {
        case .assignment(let a): a.url
        case .file(let f): f.url
        case .notice(let n): n.url
        }
    }

    var fileID: Int? {
        if case .file(let f) = item { return f.id }
        return nil
    }

    public var attachments: [LMSAttachment] {
        if case .assignment(let a) = item { return a.attachments ?? [] }
        return []
    }
}

extension LMSProposal {
    public var kind: ProposalKind {
        switch item {
        case .assignment: .lmsAssignment
        case .file: .lmsFile
        case .notice: .lmsNotice
        }
    }

    // 받기(`lms accept`)의 항목에는 내려받은 파일이 없다. 파일은 승인한 기기가 받아 `file`과 `files`에 넣는다.
    public func proposal(viewerOnly: Bool = false) -> Proposal {
        var item: [String: JSONValue] = ["key": .string(key.description)]
        if case .assignment(let a) = self.item {
            item["title"] = .string(a.title)
            // storage의 JSONFormat이 읽는 날짜 꼴이다.
            if let due = a.due { item["due"] = .string(due.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))) }
        }
        let accept = ActionProposal(command: "lms accept", input: ["items": [.object(item)]])
        return Proposal(
            kind: kind, source: .lms(self), action: kind.picksCourse ? accept : nil,
            dismissal: ActionProposal(command: "lms mark", input: ["keys": [.string(key.description)]]),
            flag: viewerOnly ? .viewerOnly : nil)
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
