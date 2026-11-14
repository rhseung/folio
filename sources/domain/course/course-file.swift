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
    // 이 문서에 적용한 제안의 ID다. 비어 있으면 파일에 쓰지 않는다.
    public var appliedProposals: [UUID]?

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
        appliedProposals = try c.decodeIfPresent([UUID].self, forKey: .appliedProposals)
    }

    public func hasApplied(_ proposal: UUID) -> Bool { appliedProposals?.contains(proposal) ?? false }

    public mutating func recordApplied(_ proposal: UUID) {
        guard !hasApplied(proposal) else { return }
        appliedProposals = (appliedProposals ?? []) + [proposal]
    }

    // iCloud가 남긴 두 사본을 합친다. 비교한 뒤 바꾸는 방법이 없어서 두 기기가 같은 제안을 거의 함께 적용할 수 있다.
    // 제안의 새 항목 ID는 제안을 만들 때 정해지므로, 항목을 ID로 합치고 적용한 제안의 ID를 모으면 한 번 적용한 것과
    // 같아진다. 같은 항목은 나중에 고친 쪽을 남긴다. 한쪽에서만 지운 항목은 되살아난다.
    public func merged(with other: CourseFile) -> CourseFile {
        let (base, rest) = Self.later(self.course, other.course) ? (self, other) : (other, self)
        var m = base
        m.materials = Self.union(base.materials, rest.materials)
        m.units = Self.union(base.units, rest.units)
        m.sessions = Self.union(base.sessions, rest.sessions)
        m.exams = Self.union(base.exams, rest.exams)
        m.assignments = Self.union(base.assignments, rest.assignments)
        m.components = Self.union(base.components, rest.components)
        m.scores = Self.union(base.scores, rest.scores)
        m.attendance = Self.union(base.attendance, rest.attendance)
        m.problemSets = Self.union(base.problemSets, rest.problemSets)
        m.recordings = Self.union(base.recordings, rest.recordings)
        m.notes = Self.union(base.notes, rest.notes)
        let applied = (base.appliedProposals ?? []) + (rest.appliedProposals ?? []).filter { !base.hasApplied($0) }
        m.appliedProposals = applied.isEmpty ? nil : applied
        return m
    }

    // 어느 사본을 먼저 주어도 결과가 같도록, 시각이 같으면 기기 ID로 고른다.
    private static func later<T: Entity>(_ a: T, _ b: T) -> Bool {
        a.updatedAt != b.updatedAt ? a.updatedAt > b.updatedAt : a.updatedBy.uuidString >= b.updatedBy.uuidString
    }

    private static func union<T: Entity>(_ base: [T], _ rest: [T]) -> [T] {
        let others = Dictionary(rest.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let kept = base.map { item in others[item.id].map { later(item, $0) ? item : $0 } ?? item }
        let ids = Set(base.map(\.id))
        return kept + rest.filter { !ids.contains($0.id) }
    }
}
