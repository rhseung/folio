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

    public var attachments: [LMSAttachment] {
        if case .assignment(let a) = item { return a.attachments ?? [] }
        return []
    }
}
