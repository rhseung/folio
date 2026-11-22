import Foundation

// 원래 값은 타입 이름이다. 액션 선언의 `Exam.ID`가 이 이름이 되고, 액션 입력 형식의 `x-folio-ref`도 같은 이름을 쓴다.
public enum ItemKind: String, CaseIterable, Codable, Sendable {
    case course = "Course"
    case semester = "Semester"
    case session = "Session"
    case exam = "Exam"
    case unit = "Unit"
    case assignment = "Assignment"
    case gradeComponent = "GradeComponent"
    case scoreEntry = "ScoreEntry"
    case material = "Material"
    case problemSet = "ProblemSet"
    case note = "Note"
    case notePath = "NotePath"
    case noteWidget = "NoteWidget"
    case recording = "Recording"
    case examPlanItem = "ExamPlanItem"
    case problem = "Problem"
    case studyCard = "StudyCard"
    case letterGrade = "LetterGrade"
    case courseCode = "CourseCode"
    case person = "Person"
    case category = "Category"
    case moveBatch = "MoveBatch"

    // 아래 switch에는 default를 두지 않는다. 새 종류는 담는 곳, 상위 종류, 링크를 정할 때까지 컴파일되지 않는다.
    public var inCourse: Bool {
        switch self {
        case .session, .exam, .unit, .assignment, .gradeComponent, .scoreEntry, .material, .problemSet, .note, .notePath, .noteWidget,
            .recording, .examPlanItem, .problem, .studyCard:
            true
        case .course, .semester, .letterGrade, .courseCode, .person, .category, .moveBatch: false
        }
    }

    // 상위 항목 안에서 찾는 종류다. 같은 액션에 상위 종류의 필드가 있으면 그 항목 안에서만 찾는다.
    public var parent: ItemKind? {
        switch self {
        case .examPlanItem: .exam
        case .problem: .problemSet
        case .studyCard: .unit
        case .course, .semester, .session, .exam, .unit, .assignment, .gradeComponent, .scoreEntry, .material, .problemSet, .note,
            .notePath, .noteWidget, .recording, .letterGrade, .courseCode, .person, .category, .moveBatch:
            nil
        }
    }

    // 명령줄에서 `<과목>/<항목>` 한 단어로 받는 종류다. 상위 항목 안에서 찾는 종류는 상위 항목 뒤에 따로 받는다.
    public var foldsIntoCourse: Bool { inCourse && parent == nil }

    // ID가 아니라 과목 폴더 기준 경로로 가리킨다.
    public var byPath: Bool { self == .notePath }

    public var link: AppLink.Kind? {
        switch self {
        case .course: .course
        case .semester: .semester
        case .session: .session
        case .exam: .exam
        case .unit: .unit
        case .assignment: .assignment
        case .material: .material
        case .problemSet: .problemSet
        case .note, .notePath: .note
        case .recording: .recording
        case .studyCard: .card
        case .person: .person
        case .gradeComponent, .scoreEntry, .noteWidget, .examPlanItem, .problem, .letterGrade, .courseCode, .category, .moveBatch: nil
        }
    }

    public init?(link: AppLink.Kind) {
        guard let kind = Self.allCases.first(where: { $0.link == link && !$0.byPath }) else { return nil }
        self = kind
    }

    public var noun: String {
        switch self {
        case .course: String(localized: .modelNounCourse)
        case .semester: String(localized: .modelNounSemester)
        case .session: String(localized: .modelNounSession)
        case .exam: String(localized: .modelNounExam)
        case .unit: String(localized: .modelNounUnit)
        case .assignment: String(localized: .modelNounAssignment)
        case .gradeComponent: String(localized: .modelNounGradeComponent)
        case .scoreEntry: String(localized: .modelNounScoreEntry)
        case .material: String(localized: .modelNounMaterial)
        case .problemSet: String(localized: .modelNounProblemSet)
        case .note, .notePath: String(localized: .modelNounNote)
        case .noteWidget: String(localized: .modelNounNoteWidget)
        case .recording: String(localized: .modelNounRecording)
        case .examPlanItem: String(localized: .modelNounExamPlanItem)
        case .problem: String(localized: .modelNounProblem)
        case .studyCard: String(localized: .modelNounCard)
        case .letterGrade: String(localized: .modelNounLetterGrade)
        case .courseCode: String(localized: .modelNounCourseCode)
        case .person: String(localized: .modelNounPerson)
        case .category: String(localized: .modelNounCategory)
        case .moveBatch: String(localized: .modelNounMoveBatch)
        }
    }
}
