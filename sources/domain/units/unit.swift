import FolioCore
import Foundation

public struct Unit: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var title: String
    public var order: Int
    public var parentId: UUID?
    private var lectures: [UnitPages]?
    // 사용자가 단원마다 직접 누르는 "다 함"이다. 앱은 활동을 보고 대신 판단하지 않는다.
    private var done: Bool?

    public var isDone: Bool {
        get { done ?? false }
        set { done = newValue ? true : nil }
    }

    public var lecturePages: [UnitPages] {
        get { lectures ?? [] }
        set { lectures = newValue.isEmpty ? nil : newValue }
    }

    public init(id: UUID = UUID(), device: DeviceID, at date: Date, title: String, order: Int, parentId: UUID? = nil) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.title = title
        self.order = order
        self.parentId = parentId
    }
}

extension Unit {
    public var labNumber: Int? {
        title.prefixMatch(of: /(?i)lab\s*(\d{1,3})(?!\d)/).flatMap { Int($0.1) }
    }

    public var labTitle: String {
        guard let m = title.prefixMatch(of: /(?i)lab\s*\d{1,3}[\s:._-]*/) else { return title }
        return String(title[m.range.upperBound...])
    }
}
