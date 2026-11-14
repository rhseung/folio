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
