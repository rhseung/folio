import FolioDomain
import FolioStorage
import Foundation

@Action("semester add", "학기 추가. 학기 폴더를 만든다. 인정학기는 출처 이름으로 _Credited/<출처> 폴더를 만든다", effect: .creates, done: "학기 '{year} {term}'을(를) 추가했습니다",
        examples: ["folio semester add 2027 spring --start 2027-03-02 --end 2027-06-18",
                   #"folio semester add 2024 credited --source "군 복무" --credited-hours 9 --dry-run  인정학기"#],
        phrases: ["학기 추가", "새 학기", "학기 만들기", "인정학기 추가"])
public struct SemesterAdd {
    @New var id: Semester.ID
    /// 연도
    @Arg var year: Int
    /// 학기
    @Arg var term: Term
    /// 개강일. 2027-03-02
    var start: LocalDate?
    /// 종강일
    var end: LocalDate?
    /// 인정학기의 인정 학점
    var creditedHours: Double?
    /// 인정학기의 출처. 영재고 AP. 폴더 이름이 된다
    var source: String?

    public func run(_ ctx: ActionContext) throws {
        var semester = Semester(id: id, device: ctx.device, at: ctx.now, year: year, term: term, start: start, end: end)
        semester.creditedHours = creditedHours
        semester.source = source
        guard term != .credited || source != nil else { throw ActionError.rule(String(localized: .errorCreditedNeedsSource(semester.name))) }
        try ctx.editTranscript { t in
            guard term == .credited || !t.semesters.contains(where: { $0.year == year && $0.term == term }) else {
                throw ActionError.rule(String(localized: .errorSemesterExists(semester.folder?.name ?? "\(year)")))
            }
            guard !t.semesters.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenSemester("\(id)"))) }
            t.semesters.append(semester)
        }
        if let folder = semester.coursesFolder {
            try ctx.io(Change(.added, folder + "/")) {
                try FileManager.default.createDirectory(at: ctx.gist.url.appending(path: folder), withIntermediateDirectories: true)
            }
        }
        ctx.made(id)
    }
}

/// The source names the term's folder, so changing it renames `_Credited/<source>` too, through `moves.jsonl`.
@Action("semester source", "인정학기의 출처 정하기. 폴더가 있으면 _Credited/<출처> 폴더 이름도 바뀌므로 확인을 받는다", effect: .moves,
        confirm: "인정학기 '{semester}'의 출처를 '{source}'(으)로 정합니다.", done: "인정학기 '{semester}'의 출처를 '{source}'(으)로 정했습니다",
        examples: [#"folio semester source "영재고 AP" "영재고 AP 과정" --dry-run"#], phrases: ["인정학기 출처", "출처 바꾸기"])
public struct SemesterSource {
    /// 인정학기
    @Arg var semester: Semester.ID
    /// 출처. 영재고 AP
    @Arg var source: String

    public func run(_ ctx: ActionContext) throws {
        guard let old = try ctx.transcript().semesters.first(where: { $0.id == semester }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundSemester))
        }
        let edit: (inout Transcript) throws -> Void = { t in
            guard !t.semesters.contains(where: { $0.id != semester && $0.term == .credited && $0.source == source }) else {
                throw ActionError.rule(String(localized: .errorCreditedSourceTaken(source)))
            }
            try t.update(\.semesters, semester) { s in
                s.source = source
                s.touch(by: ctx.device, at: ctx.now)
            }
        }

        // Checked before the move: on a regular term, `coursesFolder` is the whole semester folder.
        try ctx.checkTranscript(edit)
        if let from = old.coursesFolder, let to = StandardLayout.creditedFolder(source: source), from != to,
           FileManager.default.fileExists(atPath: ctx.gist.url.appending(path: from).path) {
            try ctx.io(Change(.moved, from, to: to)) {
                try MoveJournal.apply([PlannedMove(from: from, to: to)], in: ctx.gist.url, device: ctx.device, now: ctx.now)
            }
            ctx.invalidate()
        }
        try ctx.editTranscript(edit)
    }
}

@Action("semester set", "학기의 기간, 시험 주차, 인정 학점 바꾸기. 준 것만 바꾼다", done: "학기 '{semester}'을(를) 바꿨습니다",
        examples: ["folio semester set 2026-3 --end 2026-12-18",
                   "folio semester set 2026-3 --midterm-week 8 --final-week 16",
                   "folio semester set 2026-3 --final-week none --dry-run"],
        phrases: ["개강 종강 날짜", "시험 주차", "종강일 바꾸기", "중간고사 주차", "개강일"])
public struct SemesterSet {
    /// 학기. 2026-3 또는 "2026 fall"
    @Arg var semester: Semester.ID
    /// 개강일
    var start: Patch<LocalDate?>
    /// 종강일
    var end: Patch<LocalDate?>
    /// 중간고사 주차
    var midtermWeek: Patch<Int?>
    /// 기말고사 주차
    var finalWeek: Patch<Int?>
    /// 인정학기의 인정 학점
    var creditedHours: Patch<Double?>

    public func run(_ ctx: ActionContext) throws {
        try ctx.editTranscript { t in
            try t.update(\.semesters, semester) { s in
                start.apply(&s.start)
                end.apply(&s.end)
                midtermWeek.apply(&s.midtermWeek)
                finalWeek.apply(&s.finalWeek)
                creditedHours.apply(&s.creditedHours)
                s.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}

@Action("course add", "과목 추가. 과목 폴더와 course.json을 만든다",
        discussion: "강의 코드는 catalog.json에 있어야 한다. 폴더 이름은 `<코드><번호> <과목 이름>`이다.",
        effect: .creates, done: "과목 '{title}'을(를) 추가했습니다",
        examples: [#"folio course add EC 3101 "자료 구조" --credits 3"#, #"folio course add GS 2004-02 "전공 글쓰기" --mode pass_fail --semester 2026-3 --dry-run"#],
        phrases: ["과목 추가", "수강 신청한 과목", "새 과목"])
public struct CourseAdd {
    @New var id: Course.ID
    /// 강의 코드 앞부분. EC
    @Arg var code: CourseCode.ID
    /// 일련번호. 4207-01
    @Arg var number: String
    /// 과목 이름
    @Arg var title: String
    /// 학점
    var credits: Double = 3
    /// 평가 방식
    var mode: GradingMode = .relative
    /// 학기. 빼면 지금 학기
    var semester: Semester.ID?

    public func run(_ ctx: ActionContext) throws {
        guard let semester = try semester ?? ctx.transcript().semesters.current(on: LocalDate(ctx.now, in: ctx.calendar))?.id else {
            throw ActionError.notFound(String(localized: .errorNotFoundSemester))
        }
        try Self.create(Course(id: id, device: ctx.device, at: ctx.now, semesterId: semester, title: title, codes: [code], number: number,
                               credits: credits, gradingMode: mode), ctx)
        ctx.made(id)
    }

    static func create(_ course: Course, _ ctx: ActionContext) throws {
        guard let semester = try ctx.transcript().semesters.first(where: { $0.id == course.semesterId }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundSemester))
        }
        guard let parent = semester.coursesFolder else { throw ActionError.rule(String(localized: .errorCreditedNeedsSource(semester.name))) }

        // Course folders are found by the id in their course.json, so a second folder with this id would be unreachable.
        guard !ctx.hasFolder(course.id) else { throw ActionError.rule(String(localized: .errorIdTakenCourse("\(course.id)"))) }
        let folder = try CourseRename.folderName(title: course.title, codes: course.codes, number: course.number, catalog: ctx.catalog())
        let path = "\(parent)/\(folder)"
        guard !FileManager.default.fileExists(atPath: ctx.gist.url.appending(path: path).path) else {
            throw ActionError.rule(String(localized: .errorFolderExists(path)))
        }
        try ctx.io(Change(.added, path + "/")) { try ctx.gist.createCourse(course, folderName: folder, in: semester) }
        ctx.invalidate()
    }
}

/// course.json is the source of truth; the folder follows it. The rename goes to `moves.jsonl` so `cleanup undo` can
/// reverse it.
@Action("course rename", "과목 이름, 코드, 번호 바꾸기. 폴더 이름도 바뀌므로 확인을 받는다",
        discussion: "폴더 이동은 .folio/moves.jsonl에 남아 `folio cleanup undo`로 되돌릴 수 있다.",
        effect: .moves, confirm: "과목 '{course}'의 폴더 이름을 바꿉니다.", done: "과목 '{course}'의 이름을 바꿨습니다",
        examples: [#"folio course rename EC4207 --title "그래프 이론과 응용" --dry-run"#, "folio course rename EC4207 --number 4207-02"],
        phrases: ["과목 이름 변경", "과목 코드 변경"])
public struct CourseRename {
    /// 과목
    @Arg var course: Course.ID
    /// 과목 이름
    var title: Patch<String>
    /// 강의 코드 앞부분. 여러 개면 첫째가 주 코드
    @CLIName("code") var codes: Patch<[CourseCode.ID]>
    /// 일련번호
    var number: Patch<String>

    /// `<main code><number> <title>`.
    public static func folderName(title: String, codes: [UUID], number: String, catalog: Catalog) throws -> String {
        guard let prefix = codes.first.flatMap({ id in catalog.codes.first { $0.id == id } })?.prefix,
              let name = StandardLayout.courseFolderName(prefix: prefix, number: number, title: title) else {
            throw ActionError.rule(String(localized: .errorCourseFolderName))
        }
        return name
    }

    public func run(_ ctx: ActionContext) throws {
        let now = try ctx.file(course).course
        let (title, codes, number) = (title.value ?? now.title, codes.value ?? now.codes, number.value ?? now.number)
        let name = try Self.folderName(title: title, codes: codes, number: number, catalog: ctx.catalog())
        let from = ctx.relative(try ctx.store(course).url)
        let to = (from as NSString).deletingLastPathComponent + "/" + name

        if from != to {
            try ctx.io(Change(.moved, from, to: to)) {
                try MoveJournal.apply([PlannedMove(from: from, to: to)], in: ctx.gist.url, device: ctx.device, now: ctx.now)
                ctx.invalidate()
            }
        }
        try ctx.edit(course) {
            $0.course.title = title
            $0.course.codes = codes
            $0.course.number = number
        }
    }
}

@Action("course set", "과목의 학점, 평가 방식, 색, 아이콘, 성적, 교수, 분류, 학과 인정 바꾸기. 준 것만 바꾼다", done: "과목 '{course}'을(를) 바꿨습니다", phrases: ["교수님", "교수 이름", "학점 수정", "학점 바꾸기", "받은 성적", "학점 변경", "과목 색", "교수 지정", "성적 입력", "평가 방식"],
        cli: .manual(reason: "입력이 바꿀 항목(Field)의 목록이라, 옵션마다 항목 하나를 만들고 색 프리셋과 none을 검사한다"))
public struct CourseSet {
    public enum Field: Codable, Sendable, Equatable {
        case memo(String), credits(Double), gradingMode(GradingMode), instructors([UUID]), categories([UUID]), color(String), icon(String?),
             schedule([ClassTime]), reviews(Bool), finalGrade(UUID?), sharingApproved(Bool)
        // CaseIterable lets `folio actions --schema` list every case; Codable synthesis still uses these keys.
        enum CodingKeys: CodingKey, CaseIterable { case memo, credits, gradingMode, instructors, categories, color, icon, schedule, reviews, finalGrade, sharingApproved }
    }
    @Arg var course: Course.ID
    var fields: [Field]

    func apply(to c: inout Course) {
        for field in fields {
            switch field {
            case .memo(let v): c.memo = v
            case .credits(let v): c.credits = v
            case .gradingMode(let v): c.gradingMode = v
            case .instructors(let v): c.instructorIds = v
            case .categories(let v): c.categoryIds = v
            case .color(let v): c.color = v
            // An empty name clears it too, so the key leaves course.json instead of holding "".
            case .icon(let v): c.icon = v?.isEmpty == false ? v : nil
            case .schedule(let v):
                c.schedule = v.map { var t = $0; t.link = OnlineLink.stored(t.link); return t }
            // Nil stays nil while on, so untouched course.json files keep their shape.
            case .reviews(let v): if v != (c.reviews != false) { c.reviews = v ? nil : false }
            case .finalGrade(let v): c.finalGrade = v
            case .sharingApproved(let v): c.sharingApproved = v ? true : nil
            }
        }
    }

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { apply(to: &$0.course) }
    }
}

@Action("requirement set", "졸업 요건과 학생 정보 바꾸기. 준 것만 바꾼다", discussion: "과정은 major, doubleMajor, minor, intensive.",
        done: "졸업 요건을 바꿨습니다", examples: ["folio requirement set --admission-year 2023", "folio requirement set --total-credits 130 --min-gpa 2.0",
                   "folio requirement set --program major:EC --program minor:GS --dry-run"],
        phrases: ["복수전공 추가", "부전공", "전공 추가", "입학 연도", "전공 선언", "복수전공"])
public struct GraduationSet {
    /// 졸업 학점
    var totalCredits: Patch<Double>
    /// 최저 평점
    var minGPA: Patch<Double>
    /// 입학 연도(학번)
    var admissionYear: Patch<Int?>
    /// 교수에게 메일을 보낼 계정
    var email: Patch<String>
    /// 선언한 과정과 그 학과의 강의 코드. 주면 목록 전체를 바꾼다
    @CLIName("program") @Parsed("program", "과정:강의 코드 앞부분. major:EC") var programs: Patch<[StudentProgram]>

    public func run(_ ctx: ActionContext) throws {
        try ctx.editTranscript { t in
            totalCredits.apply(&t.graduation.totalCredits)
            minGPA.apply(&t.graduation.minGPA)
            admissionYear.apply(&t.graduation.admissionYear)
            email.apply(&t.graduation.email)
            programs.apply(&t.graduation.programs)
        }
    }
}

/// The categories come from the handbook here, not from the caller, so the app and the CLI apply what
/// `requirement check` lists. Every course is matched before any is written, so a course with no suggestion leaves
/// the others untouched.
@Action("requirement accept", "학사편람의 분류 제안 받아들이기. 여러 과목이면 확인을 받는다",
        confirm: "과목 {courses}의 분류를 학사편람대로 바꿉니다.", done: "과목 {courses}의 분류를 학사편람대로 바꿨습니다",
        phrases: ["학사편람 분류 적용", "분류 제안 적용", "제안 모두 적용"], cli: .manual(reason: "과목을 빼면 졸업 요건 검사가 제안한 과목을 모두 고른다"))
public struct RequirementAccept {
    /// 과목
    @Arg var courses: [Course.ID]

    public func run(_ ctx: ActionContext) throws {
        let catalog = try ctx.catalog().scoped(to: ctx.transcript().graduation.programs)
        let picked = try courses.map { try ctx.file($0).course }
        let suggested = Dictionary(keepingFirst: HandbookClassifier.suggest(courses: picked, semesters: try ctx.transcript().semesters, catalog: catalog)
            .map { ($0.courseId, $0.categoryIds) })
        let changes = try picked.map { c in
            guard let ids = suggested[c.id] else { throw ActionError.rule(String(localized: .errorRequirementNoSuggestion(c.title))) }
            return (c.id, ids)
        }
        for (id, ids) in changes { try ctx.edit(id) { $0.course.categoryIds = ids } }
    }
}

/// Rows that changed are stamped as edited from this device. Unknown keys are kept.
@Action("catalog set", "catalog.json을 파일 내용으로 바꾸기. 바뀐 행만 수정 시각이 바뀐다",
        discussion: "`folio catalog show --json`으로 받은 파일을 고쳐서 넣는다. 모르는 필드는 남는다.",
        done: "카탈로그를 바꿨습니다", examples: ["folio catalog set --file catalog.json --dry-run"], phrases: ["카탈로그 수정"])
public struct CatalogSet {
    /// catalog.json 형식의 파일
    @CLIName("file") @FromFile("path") var catalog: Catalog

    public func run(_ ctx: ActionContext) throws {
        try ctx.editCatalog { old in
            func touched<E: Entity>(_ new: [E], _ old: [E]) -> [E] {
                let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                return new.map { item in
                    guard let previous = before[item.id], previous != item else { return item }
                    var item = item
                    item.touch(by: ctx.device, at: ctx.now)
                    return item
                }
            }

            var new = catalog
            new.codes = touched(catalog.codes, old.codes)
            new.categories = touched(catalog.categories, old.categories)
            new.letterGrades = touched(catalog.letterGrades, old.letterGrades)
            new.people = touched(catalog.people, old.people)
            old = new
        }
    }
}

/// One value by its key path, so a command changes one setting without sending the rest; the app's settings screen
/// sends the whole file instead.
@Action("settings set", "설정 하나를 바꾸거나 settings.json 전체를 파일 내용으로 바꾸기", discussion: """
        필드는 settings.json의 이름을 점으로 이어 쓴다(`folio settings show --json`). 값은 JSON으로 읽고, JSON이 아니면 글자로 읽는다.
        있는 필드만 바꿀 수 있다. 모양이 맞지 않는 값은 쓰지 않는다(종료 코드 2).
        """,
        done: "설정을 바꿨습니다", examples: ["folio settings set dayBoundaryMinutes 300", #"folio settings set review.intervals "[1, 3, 7, 14, 30]" --dry-run"#,
                   "folio settings set --file settings.json --dry-run"],
        phrases: ["설정 변경", "하루 경계", "복습 간격", "알림 시간"])
public struct SettingsSet {
    /// 필드. 예: review.intervals
    @Arg var field: String?
    /// 새 값
    @Arg var value: JSONValue?
    /// settings.json 형식의 파일. 필드 대신 설정 전체를 바꾼다
    @CLIName("file") @FromFile("path") var settings: Settings?

    public func run(_ ctx: ActionContext) throws {
        let new: Settings
        if let settings {
            guard field == nil, value == nil else { throw ActionError.input(String(localized: .errorSettingsFieldOrFile)) }
            new = settings
        } else {
            guard let field, let value else { throw ActionError.input(String(localized: .errorSettingsNeedsFieldAndValue)) }
            var root = try JSONValue(ctx.settings())
            try root.set(field.split(separator: ".").map(String.init), to: value, path: field)
            do {
                new = try JSONDecoder.folio.decode(Settings.self, from: JSONEncoder.folio.encode(root))
            } catch let e as DecodingError {
                throw ActionError.input(String(localized: .errorSettingsBadValue(field, e.summary)))
            }
        }
        try ctx.editSettings { $0 = new }
    }
}

extension JSONValue {
    /// Replaces the value at an existing key path; a key that isn't there is a typo, not a new setting.
    mutating func set(_ keys: [String], to value: JSONValue, path: String) throws {
        guard let key = keys.first else { self = value; return }
        guard case .object(var o) = self, var child = o[key] else {
            let known = if case .object(let o) = self { o.keys.sorted().joined(separator: ", ") } else { "" }
            throw ActionError.input(String(localized: .errorSettingsUnknownField(path, known)))
        }
        try child.set(Array(keys.dropFirst()), to: value, path: path)
        o[key] = child
        self = .object(o)
    }
}

extension CourseSet {
    public init(course: Course.ID, _ fields: [Field]) { self.init(course: course, fields: fields) }
}
