import FolioCore
import Foundation

public struct ExamPlanItem: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var day: LocalDate
    public var target: ExamPlanTarget
    // 사용자가 쓴 할 일의 글이다. 앱이 놓은 항목은 대상으로 이름을 그린다.
    public var title: String
    // 사용자가 날짜를 고치거나 직접 더한 항목이다. 다시 놓을 때 그대로 둔다.
    public var edited: Bool?
    // 사용자가 뺀 앱의 항목이다. 다시 놓을 때 같은 대상을 넣지 않도록 지우지 않고 남긴다.
    public var removed: Bool?
    // 미루기 전에 있던 날이다. 미룬 항목은 옮겨 간 날에서도 밀림으로 보인다.
    public var postponedFrom: LocalDate?

    public init(
        id: UUID = UUID(), day: LocalDate, target: ExamPlanTarget, title: String = "", edited: Bool? = nil, postponedFrom: LocalDate? = nil
    ) {
        self.id = id
        self.day = day
        self.target = target
        self.title = title
        self.edited = edited
        self.postponedFrom = postponedFrom
    }

    public var isEdited: Bool { edited ?? false }
    public var isRemoved: Bool { removed ?? false }

    // 못 하고 지난 항목은 파일의 날짜를 고치지 않고 오늘에 얹어 보인다. 공부일이 바뀔 때마다 파일을 쓰지 않기 위해서다.
    public func shownDay(today: LocalDate, done: Bool) -> LocalDate { !done && day < today ? today : day }

    // 밀린 항목이 원래 있던 날이다. 제날에 있거나 끝낸 항목은 nil이다.
    public func lateFrom(today: LocalDate, done: Bool) -> LocalDate? {
        if done { return nil }
        return postponedFrom ?? (day < today ? day : nil)
    }
}
