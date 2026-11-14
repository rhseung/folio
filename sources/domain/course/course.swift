import Foundation

public struct Course: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var semesterId: UUID?
    public var title: String
    public var titleEn: String
    public var codes: [UUID]
    public var number: String
    public var categoryIds: [UUID]
    public var instructorIds: [UUID]
    public var credits: Double
    public var gradingMode: GradingMode
    public var finalGrade: UUID?
    public var absoluteScore: Double?
    public var targetGrade: UUID?
    public var countsTowardMajor: Bool?
    public var sharingApproved: Bool?
    public var retakeOf: UUID?
    public var reviews: Bool?
    public var schedule: [ClassTime]
    public var color: String
    public var icon: String?
    public var folderRoles: [String: MaterialRole]
    public var syllabusMaterialId: UUID?
    public var memo: String

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date,
        semesterId: UUID? = nil, title: String, titleEn: String = "", codes: [UUID] = [], number: String = "",
        categoryIds: [UUID] = [], instructorIds: [UUID] = [], credits: Double = 3,
        gradingMode: GradingMode = .relative, schedule: [ClassTime] = [], color: String = "", memo: String = ""
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.semesterId = semesterId
        self.title = title
        self.titleEn = titleEn
        self.codes = codes
        self.number = number
        self.categoryIds = categoryIds
        self.instructorIds = instructorIds
        self.credits = credits
        self.gradingMode = gradingMode
        self.schedule = schedule
        self.color = color
        self.folderRoles = [:]
        self.memo = memo
    }
}
