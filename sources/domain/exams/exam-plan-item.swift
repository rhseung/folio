import FolioCore
import Foundation

public struct ExamPlanItem: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var day: LocalDate
    public var target: ExamPlanTarget
    // 사용자가 쓴 할 일의 글이다. 앱이 짠 항목은 대상으로 이름을 그린다.
    public var title: String
    // 사용자가 날짜를 고치거나 직접 더한 항목이다. 다시 짤 때 그대로 둔다.
    public var edited: Bool?
    // 사용자가 뺀 앱의 항목이다. 다시 짤 때 같은 대상을 넣지 않도록 지우지 않고 남긴다.
    public var removed: Bool?
    // 지난 날에 못 해서 오늘로 옮긴 항목이다.
    public var carried: Bool?
    // 개념 모름으로 틀린 문제의 렉처 쪽이다. 이 항목에서 다시 본다.
    public var pages: [ProblemPage]?

    public init(
        id: UUID = UUID(), day: LocalDate, target: ExamPlanTarget, title: String = "", edited: Bool? = nil, carried: Bool? = nil,
        pages: [ProblemPage]? = nil
    ) {
        self.id = id
        self.day = day
        self.target = target
        self.title = title
        self.edited = edited
        self.carried = carried
        self.pages = pages
    }

    public var isEdited: Bool { edited ?? false }
    public var isRemoved: Bool { removed ?? false }
    public var isCarried: Bool { carried ?? false }
}
