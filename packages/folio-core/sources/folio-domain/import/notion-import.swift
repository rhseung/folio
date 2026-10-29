import Foundation

/// Notion data as read through the Notion MCP (docs/SPEC.md "기존 데이터 이전"), in a Notion-independent shape.
/// IDs are the Notion page IDs, so importing twice yields the same entity IDs.
/// Judgement calls the spec assigns to Claude (rule text → aggregation and attendance caps, exam times written in
/// page bodies) are already resolved in this file; the original text stays in `policy.notes` and `memo`.
public struct NotionExport: Codable, Sendable {
    public struct SemesterRow: Codable, Sendable {
        public var id: UUID
        /// `2026 가을학기`, or `인정학기` for credited terms.
        public var title: String
        public var start: LocalDate?
        public var end: LocalDate?
    }

    public struct GradeRow: Codable, Sendable {
        public var id: UUID
        public var symbol: String
        public var points: Double?
        public var countsInCredits: Bool
    }

    public struct CodeRow: Codable, Sendable {
        public var id: UUID
        public var prefix: String
        public var department: String
        public var program: String
    }

    public struct CategoryRow: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var group: String
        public var parentId: UUID?
        public var minCredits: Double?
        public var maxCredits: Double?
    }

    public struct PersonRow: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var email: String?
        public var memo: String?
        public var role: PersonRole?
    }

    public struct ExamRow: Codable, Sendable {
        public var start: Date?
        public var end: Date?
        public var location: String?
    }

    public struct EntryRow: Codable, Sendable {
        public var id: UUID
        public var title: String
        public var score: Double
        public var max: Double
    }

    public struct ComponentRow: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var weight: Double
        public var aggregation: Aggregation?
        public var expectedCount: Int?
        public var entries: [EntryRow]?
    }

    public struct CapRow: Codable, Sendable {
        public var absences: Int
        /// Letter grade symbol, e.g. `B0`.
        public var grade: String
    }

    public struct PolicyRow: Codable, Sendable {
        public var caps: [CapRow]?
        public var minAttendanceRatio: Double?
        public var latePolicy: String?
        public var notes: String?
    }

    public struct CourseRow: Codable, Sendable {
        public var id: UUID
        public var title: String
        public var titleEn: String?
        /// `4207-01`; the part before `-` is the course number used in folder names.
        public var number: String
        public var credits: Double
        /// `상대평가`, `절대평가` or `S/U`.
        public var mode: String
        public var gradeId: UUID?
        public var absoluteScore: Double?
        public var semesterId: UUID
        public var codeIds: [UUID]
        public var categoryIds: [UUID]?
        public var personIds: [UUID]?
        public var midterm: ExamRow?
        public var final: ExamRow?
        public var components: [ComponentRow]?
        public var policy: PolicyRow?
        public var memo: String?
    }

    public var semesters: [SemesterRow]
    public var grades: [GradeRow]
    public var codes: [CodeRow]
    public var categories: [CategoryRow]
    public var people: [PersonRow]
    public var courses: [CourseRow]
}

public struct NotionImportResult: Sendable, Equatable {
    public var transcript: Transcript
    public var catalog: Catalog
    /// GIST-relative course folder path → its course.json.
    public var courseFiles: [String: CourseFile]
    /// Messages for things the user should check (unknown semester titles, unmatched references, ...).
    public var warnings: [String]

    public init(transcript: Transcript, catalog: Catalog, courseFiles: [String: CourseFile], warnings: [String]) {
        self.transcript = transcript
        self.catalog = catalog
        self.courseFiles = courseFiles
        self.warnings = warnings
    }
}

public enum NotionImporter {
    static let termNames: [String: Term] = ["봄": .spring, "여름": .summer, "가을": .fall, "겨울": .winter]
    static let creditedTitle = "인정학기"
    static let majorGroup = "전공"
    static let gradingModes: [String: GradingMode] = ["상대평가": .relative, "절대평가": .absolute, "S/U": .passFail]

    /// `2026 가을학기` → (2026, fall). Credited terms take the earliest regular year so ordering stays sensible.
    static func term(of title: String) -> (year: Int, term: Term)? {
        guard let m = title.firstMatch(of: /(\d{4})\s*(봄|여름|가을|겨울)학기/), let term = termNames[String(m.2)] else { return nil }
        return (Int(m.1)!, term)
    }

    public static func convert(_ export: NotionExport, gist: FolderTree, device: DeviceID, now: Date) -> NotionImportResult {
        var warnings: [String] = []

        let catalog = Catalog(
            codes: export.codes.map { CourseCode(id: $0.id, device: device, at: now, prefix: $0.prefix, department: $0.department, program: $0.program) },
            categories: export.categories.map {
                Category(id: $0.id, device: device, at: now, name: $0.name, group: $0.group, isMajor: $0.group == majorGroup,
                         parentId: $0.parentId, minCredits: $0.minCredits, maxCredits: $0.maxCredits)
            },
            letterGrades: export.grades.map {
                LetterGrade(id: $0.id, device: device, at: now, symbol: $0.symbol, points: $0.points,
                            countsInGpa: $0.points != nil, countsInCredits: $0.countsInCredits)
            },
            people: export.people.map {
                Person(id: $0.id, device: device, at: now, name: $0.name, email: $0.email ?? "", role: $0.role ?? .professor, memo: $0.memo ?? "")
            }
        )

        let regularYears = export.semesters.compactMap { term(of: $0.title)?.year }
        var semesters: [Semester] = []
        for row in export.semesters {
            if let (year, term) = term(of: row.title) {
                semesters.append(Semester(id: row.id, device: device, at: now, year: year, term: term, start: row.start, end: row.end))
            } else if row.title == creditedTitle {
                let hours = export.courses.filter { $0.semesterId == row.id }.reduce(0) { $0 + $1.credits }
                semesters.append(Semester(id: row.id, device: device, at: now, year: regularYears.min() ?? 0, term: .credited, creditedHours: hours))
            } else {
                warnings.append(String(localized: .importNotionUnknownTerm(row.title)))
            }
        }

        let gradeBySymbol = Dictionary(catalog.letterGrades.map { ($0.symbol, $0.id) }, uniquingKeysWith: { a, _ in a })
        let prefixes = Dictionary(keepingFirst: catalog.codes.map { ($0.id, $0.prefix) })
        var transcriptCourses: [Course] = []
        var courseFiles: [String: CourseFile] = [:]

        for row in export.courses {
            guard let semester = semesters.first(where: { $0.id == row.semesterId }) else {
                warnings.append(String(localized: .importNotionNoSemester(row.title)))
                continue
            }
            var course = Course(
                id: row.id, device: device, at: now, semesterId: semester.id, title: row.title, titleEn: row.titleEn ?? "",
                codes: row.codeIds, number: row.number, categoryIds: row.categoryIds ?? [], instructorIds: row.personIds ?? [],
                credits: row.credits, gradingMode: gradingModes[row.mode] ?? .relative, memo: row.memo ?? ""
            )
            course.finalGrade = row.gradeId
            course.absoluteScore = row.absoluteScore

            guard let folder = courseFolder(for: row, in: semester, prefixes: prefixes, gist: gist) else {
                transcriptCourses.append(course)
                continue
            }

            var file = CourseFile(course: course)
            for (kind, exam) in [(ExamKind.midterm, row.midterm), (.final, row.final)] {
                guard let exam else { continue }
                file.exams.append(Exam(device: device, at: now, kind: kind, title: kind.folderName() ?? "", start: exam.start, end: exam.end, location: exam.location ?? ""))
            }
            for (order, c) in (row.components ?? []).enumerated() {
                file.components.append(GradeComponent(id: c.id, device: device, at: now, name: c.name, weight: c.weight, order: order,
                                                      aggregation: c.aggregation ?? .sum, expectedCount: c.expectedCount))
                file.scores += (c.entries ?? []).map {
                    ScoreEntry(id: $0.id, device: device, at: now, componentId: c.id, title: $0.title, score: $0.score, max: $0.max)
                }
            }
            if let p = row.policy {
                var caps: [AttendanceCap] = []
                for cap in p.caps ?? [] {
                    if let grade = gradeBySymbol[cap.grade] {
                        caps.append(AttendanceCap(absences: cap.absences, maxGrade: grade))
                    } else {
                        warnings.append(String(localized: .importNotionCapGradeMissing(row.title, cap.grade)))
                    }
                }
                file.policy = GradePolicy(attendanceCap: caps, minAttendanceRatio: p.minAttendanceRatio, latePolicy: p.latePolicy, notes: p.notes ?? "")
            }
            courseFiles[folder] = file
        }

        return NotionImportResult(
            transcript: Transcript(semesters: semesters, courses: transcriptCourses),
            catalog: catalog, courseFiles: courseFiles, warnings: warnings
        )
    }

    /// `<semester folder>/<code><number> ...`, trying every cross-listed code (docs/SPEC.md: 학기와 과목 코드로 짝짓는다).
    static func courseFolder(for row: NotionExport.CourseRow, in semester: Semester, prefixes: [UUID: String], gist: FolderTree) -> String? {
        guard let folder = semester.folder, let node = gist[child: folder.name] else { return nil }
        let number = row.number.split(separator: "-").first.map(String.init) ?? row.number
        let codes = row.codeIds.compactMap { prefixes[$0] }.map { "\($0)\(number) " }
        return node.children
            .first { child in !child.isFile && codes.contains { child.name.hasPrefix($0) } }
            .map { "\(folder.name)/\($0.name)" }
    }
}
