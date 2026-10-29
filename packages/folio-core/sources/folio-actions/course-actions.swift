import FolioDomain
import FolioStorage
import Foundation

@Action("semester add", "학기 추가. 학기 폴더를 만든다. 인정학기는 폴더 없이 기록만", effect: .creates, done: "학기 '{year} {term}'을(를) 추가했습니다",
        examples: ["folio semester add 2027 spring --start 2027-03-02 --end 2027-06-18",
                   "folio semester add 2024 credited --credited-hours 9 --dry-run  군 복무 인정학기"],
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

    public func run(_ ctx: ActionContext) throws {
        var semester = Semester(id: id, device: ctx.device, at: ctx.now, year: year, term: term, start: start, end: end)
        semester.creditedHours = creditedHours
        try ctx.editTranscript { t in
            guard term == .credited || !t.semesters.contains(where: { $0.year == year && $0.term == term }) else {
                throw ActionError.rule(String(localized: .errorSemesterExists(semester.folder?.name ?? "\(year)")))
            }
            guard !t.semesters.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenSemester("\(id)"))) }
            t.semesters.append(semester)
        }
        if let folder = semester.folder {
            try ctx.io(Change(.added, folder.name + "/")) {
                try FileManager.default.createDirectory(at: ctx.gist.url.appending(path: folder.name), withIntermediateDirectories: true)
            }
        }
        ctx.made(id)
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

/// Creates the course folder `<code><number> <title>` with its course.json.
@Action("course add", "과목 추가. 과목 폴더와 course.json을 만든다", effect: .creates, done: "과목 '{title}'을(를) 추가했습니다", phrases: ["과목 추가", "수강 신청한 과목", "새 과목"], cli: .manual)
public struct CourseAdd {
    @New var id: Course.ID
    var semester: Semester.ID
    var title: String
    var code: CourseCode.ID
    var number: String
    var credits: Double
    var mode: GradingMode

    public func run(_ ctx: ActionContext) throws {
        guard let semester = try ctx.transcript().semesters.first(where: { $0.id == self.semester }), let semesterFolder = semester.folder else {
            throw ActionError.notFound(String(localized: .errorNotFoundSemester))
        }
        // Course folders are found by the id in their course.json, so a second folder with this id would be unreachable.
        guard !ctx.hasFolder(id) else { throw ActionError.rule(String(localized: .errorIdTakenCourse("\(id)"))) }
        let folder = try CourseRename.folderName(title: title, codes: [code], number: number, catalog: ctx.catalog())
        let course = Course(id: id, device: ctx.device, at: ctx.now, semesterId: semester.id, title: title, codes: [code], number: number,
                            credits: credits, gradingMode: mode)
        let path = "\(semesterFolder.name)/\(folder)"
        guard !FileManager.default.fileExists(atPath: ctx.gist.url.appending(path: path).path) else {
            throw ActionError.rule(String(localized: .errorFolderExists(path)))
        }
        try ctx.io(Change(.added, path + "/")) { try ctx.gist.createCourse(course, folderName: folder, in: semester) }
        ctx.invalidate()
        ctx.made(id)
    }
}

/// course.json is the source of truth; the folder follows it. The rename goes to `moves.jsonl` so `cleanup undo` can
/// reverse it.
@Action("course rename", "과목 이름, 코드, 번호 바꾸기. 폴더 이름도 바뀌므로 확인을 받는다", effect: .moves, confirm: "과목 '{course}'의 폴더 이름을 바꿉니다.", done: "과목 '{course}'의 이름을 바꿨습니다", phrases: ["과목 이름 변경", "과목 코드 변경"], cli: .manual)
public struct CourseRename {
    @Arg var course: Course.ID
    var title: String
    var codes: [CourseCode.ID]
    var number: String

    /// `<main code><number> <title>`.
    public static func folderName(title: String, codes: [UUID], number: String, catalog: Catalog) throws -> String {
        guard let prefix = codes.first.flatMap({ id in catalog.codes.first { $0.id == id } })?.prefix,
              let name = StandardLayout.courseFolderName(prefix: prefix, number: number, title: title) else {
            throw ActionError.rule(String(localized: .errorCourseFolderName))
        }
        return name
    }

    public func run(_ ctx: ActionContext) throws {
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

/// A course with a folder saves to its course.json; one without (credited terms, colloquia) to transcript.json. The
/// command reads names (grades, people, categories) into ids, so it is written by hand.
@Action("course set", "과목의 학점, 평가 방식, 색, 아이콘, 성적, 교수, 분류, 학과 인정 바꾸기. 준 것만 바꾼다", done: "과목 '{course}'을(를) 바꿨습니다", phrases: ["교수님", "교수 이름", "학점 수정", "학점 바꾸기", "받은 성적", "학점 변경", "과목 색", "교수 지정", "성적 입력", "평가 방식"], cli: .manual)
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
            case .schedule(let v): c.schedule = v
            // Nil stays nil while on, so untouched course.json files keep their shape.
            case .reviews(let v): if v != (c.reviews != false) { c.reviews = v ? nil : false }
            case .finalGrade(let v): c.finalGrade = v
            case .sharingApproved(let v): c.sharingApproved = v ? true : nil
            }
        }
    }

    public func run(_ ctx: ActionContext) throws {
        if ctx.hasFolder(course) {
            try ctx.edit(course) { apply(to: &$0.course) }
            return
        }
        try ctx.editTranscript { t in
            guard let i = t.courses.firstIndex(where: { $0.id == course }) else { throw ActionError.notFound(String(localized: .errorNotFoundCourse)) }
            apply(to: &t.courses[i])
            t.courses[i].touch(by: ctx.device, at: ctx.now)
        }
    }
}

@Action("requirement set", "졸업 요건과 학생 정보 바꾸기. 준 것만 바꾼다", done: "졸업 요건을 바꿨습니다", phrases: ["복수전공 추가", "부전공", "전공 추가", "입학 연도", "전공 선언", "복수전공"], cli: .manual)
public struct GraduationSet {
    var rule: GraduationRule

    public func run(_ ctx: ActionContext) throws {
        try ctx.editTranscript { $0.graduation = rule }
    }
}

/// Replaces catalog.json's tables; rows that changed are stamped as edited from this device. Unknown keys are kept.
@Action("catalog set", "catalog.json을 파일 내용으로 바꾸기. 바뀐 행만 수정 시각이 바뀐다", done: "카탈로그를 바꿨습니다", phrases: ["카탈로그 수정"], cli: .manual)
public struct CatalogSet {
    var catalog: Catalog

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

@Action("settings set", "설정 하나를 바꾸거나 settings.json 전체를 파일 내용으로 바꾸기", done: "설정을 바꿨습니다", phrases: ["설정 변경", "하루 경계", "복습 간격", "알림 시간"], cli: .manual)
public struct SettingsSet {
    var settings: Settings

    public func run(_ ctx: ActionContext) throws {
        try ctx.editSettings { $0 = settings }
    }
}

extension CourseSet {
    public init(course: Course.ID, _ fields: [Field]) { self.init(course: course, fields: fields) }
}
