import Foundation

public struct Exam: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var title: String
    public var start: Date?
    public var end: Date?
    public var location: String
    public var scopeUnitIds: [UUID]
    public var scopeText: String
    public var allowed: String
    public var componentId: UUID?
    public var memo: String
    public var plan: [ExamPlanItem]
    // 폴더 이름을 제목에서 계산하지 않고 저장한다. 그래야 제목을 바꾼 시험도 폴더를 지키고, 제목으로 폴더 이름을 짓기
    // 전에 만든 폴더(중간고사의 `Midterm`)도 계속 그 파일을 가리킨다.
    public var folder: String?

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, title: String, start: Date? = nil, end: Date? = nil, location: String = "",
        folder: String? = nil
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.scopeUnitIds = []
        self.scopeText = ""
        self.allowed = ""
        self.memo = ""
        self.plan = []
        self.folder = folder
    }
}

extension Exam {
    // `plan`은 첫 course.json 파일들보다 나중에 생겼으므로, 키가 없으면 계획이 없다는 뜻이다.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        updatedBy = try c.decode(DeviceID.self, forKey: .updatedBy)
        title = try c.decode(String.self, forKey: .title)
        start = try c.decodeIfPresent(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
        location = try c.decode(String.self, forKey: .location)
        scopeUnitIds = try c.decode([UUID].self, forKey: .scopeUnitIds)
        scopeText = try c.decode(String.self, forKey: .scopeText)
        allowed = try c.decode(String.self, forKey: .allowed)
        componentId = try c.decodeIfPresent(UUID.self, forKey: .componentId)
        memo = try c.decode(String.self, forKey: .memo)
        plan = try c.decodeIfPresent([ExamPlanItem].self, forKey: .plan) ?? []
        folder = try c.decodeIfPresent(String.self, forKey: .folder)
    }
}
