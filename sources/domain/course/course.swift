import Foundation

public struct CourseFile: Codable, Sendable, Equatable {
    public var course: Course
    public var materials: [Material]
    public var units: [Unit]
    public var sessions: [Session]
    public var exams: [Exam]
    public var assignments: [Assignment]
    public var components: [GradeComponent]
    public var scores: [ScoreEntry]
    public var policy: GradePolicy
    public var attendance: [Attendance]
    public var problemSets: [ProblemSet]
    public var recordings: [Recording]
    public var notes: [NoteEntry]

    public init(
        course: Course, materials: [Material] = [], units: [Unit] = [], sessions: [Session] = [], exams: [Exam] = [],
        assignments: [Assignment] = [],
        components: [GradeComponent] = [], scores: [ScoreEntry] = [], policy: GradePolicy = .init(), attendance: [Attendance] = [],
        problemSets: [ProblemSet] = [],
        recordings: [Recording] = [], notes: [NoteEntry] = []
    ) {
        self.course = course
        self.materials = materials
        self.units = units
        self.sessions = sessions
        self.exams = exams
        self.assignments = assignments
        self.components = components
        self.scores = scores
        self.policy = policy
        self.attendance = attendance
        self.problemSets = problemSets
        self.recordings = recordings
        self.notes = notes
    }

    // 빠진 구역은 빈 값으로 읽으므로, 구역을 더해도 스키마 마이그레이션이 필요 없다.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        course = try c.decode(Course.self, forKey: .course)
        materials = try c.decodeIfPresent([Material].self, forKey: .materials) ?? []
        units = try c.decodeIfPresent([Unit].self, forKey: .units) ?? []
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        exams = try c.decodeIfPresent([Exam].self, forKey: .exams) ?? []
        assignments = try c.decodeIfPresent([Assignment].self, forKey: .assignments) ?? []
        components = try c.decodeIfPresent([GradeComponent].self, forKey: .components) ?? []
        scores = try c.decodeIfPresent([ScoreEntry].self, forKey: .scores) ?? []
        policy = try c.decodeIfPresent(GradePolicy.self, forKey: .policy) ?? .init()
        attendance = try c.decodeIfPresent([Attendance].self, forKey: .attendance) ?? []
        problemSets = try c.decodeIfPresent([ProblemSet].self, forKey: .problemSets) ?? []
        recordings = try c.decodeIfPresent([Recording].self, forKey: .recordings) ?? []
        notes = try c.decodeIfPresent([NoteEntry].self, forKey: .notes) ?? []
    }
}

public enum GradingMode: String, Codable, Sendable, CaseIterable {
    case relative
    case absolute
    case passFail = "pass_fail"
}

public struct ClassTime: Codable, Sendable, Hashable {
    // ISO 8601 요일이다. 1은 월요일, 7은 일요일이다.
    public var weekday: Int
    public static let weekdayNames = [
        LocalizedStringResource.weekdayMon, .weekdayTue, .weekdayWed, .weekdayThu, .weekdayFri, .weekdaySat, .weekdaySun,
    ]
    .map { String(localized: $0) }
    public var startMinute: Int
    public var endMinute: Int
    public var room: String
    public var link: String?

    public init(weekday: Int, startMinute: Int, endMinute: Int, room: String = "", link: String? = nil) {
        self.weekday = weekday
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.room = room
        self.link = link
    }
}

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
