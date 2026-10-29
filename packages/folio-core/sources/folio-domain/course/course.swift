import Foundation

/// `<course>/.folio/course.json`. Keys this version doesn't model are preserved on save by Storage.
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

    public init(course: Course, materials: [Material] = [], units: [Unit] = [], sessions: [Session] = [], exams: [Exam] = [], assignments: [Assignment] = [],
                components: [GradeComponent] = [], scores: [ScoreEntry] = [], policy: GradePolicy = .init(), attendance: [Attendance] = [], problemSets: [ProblemSet] = [],
                recordings: [Recording] = []) {
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
    }

    // A missing section means empty, so adding a section never needs a schema migration.
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
    }
}

public enum GradingMode: String, Codable, Sendable, CaseIterable {
    case relative
    case absolute
    case passFail = "pass_fail"
}

/// One weekly class slot. Times are minutes from midnight in local time.
public struct ClassTime: Codable, Sendable, Hashable {
    /// ISO 8601 weekday: 1 = Monday ... 7 = Sunday.
    public var weekday: Int
    /// Indexed by `weekday - 1`.
    public static let weekdayNames = [LocalizedStringResource.weekdayMon, .weekdayTue, .weekdayWed, .weekdayThu, .weekdayFri, .weekdaySat, .weekdaySun]
        .map { String(localized: $0) }
    public var startMinute: Int
    public var endMinute: Int
    public var room: String

    public init(weekday: Int, startMinute: Int, endMinute: Int, room: String = "") {
        self.weekday = weekday
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.room = room
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
    /// CourseCode IDs from catalog.json; the first is the primary code.
    public var codes: [UUID]
    /// Serial number, e.g. `4207-01`.
    public var number: String
    public var categoryIds: [UUID]
    public var instructorIds: [UUID]
    public var credits: Double
    public var gradingMode: GradingMode
    public var finalGrade: UUID?
    public var absoluteScore: Double?
    public var targetGrade: UUID?
    /// Nil means infer from the categories.
    public var countsTowardMajor: Bool?
    /// 학과별 인정 과목 (학사편람): lets the course count toward a double major and the major without carrying both codes.
    public var sharingApproved: Bool?
    public var retakeOf: UUID?
    /// False for courses with nothing to review (no exams, e.g. some liberal arts); nil means on.
    public var reviews: Bool?
    public var schedule: [ClassTime]
    public var color: String
    /// An SF Symbol name the course is shown with, in its color; nil shows the app's default (a book).
    public var icon: String?
    /// Exceptions to the standard layout: relative folder path -> role. Empty by default.
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
