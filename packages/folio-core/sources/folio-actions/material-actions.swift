import FolioDomain
import FolioStorage
import Foundation

/// The command reads the pages as one `--pages 3-12`, so it is written by hand.
@Action("material link", "자료를 회차에 연결하거나 떼기", done: "자료 '{material}'과(와) 회차 '{session}'의 연결을 바꿨습니다",
        phrases: ["자료 수업 연결", "슬라이드 회차에 붙이기"], cli: .manual)
public struct MaterialLinkSession {
    @Arg var course: Course.ID
    @Arg var material: Material.ID
    @Arg var session: Session.ID
    @Off("off") var linked = true
    var firstPage: Int?
    var lastPage: Int?

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            _ = try index(session, in: f.sessions, .valueSession)
            if linked { f.linkMaterial(material, session: session, firstPage: firstPage, lastPage: lastPage) } else { f.unlinkMaterial(material, session: session) }
        }
    }
}

@Action("material link-unit", "자료를 단원에 연결하거나 떼기", done: "자료 '{material}'과(와) 단원 '{unit}'의 연결을 바꿨습니다",
        examples: ["folio material link-unit EC4207/05_Matchings.pdf 매칭", "folio material link-unit EC4207/05_Matchings.pdf 매칭 --off"],
        phrases: ["자료 단원 연결"])
public struct MaterialLinkUnit {
    /// 과목
    @Arg var course: Course.ID
    /// 자료
    @Arg var material: Material.ID
    /// 같은 과목의 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 연결 떼기
    @Off("off") var linked = true

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            _ = try index(unit, in: f.units, .valueUnit)
            f.setMaterial(material, unit: unit, linked: linked)
        }
    }
}

/// The status comes before the materials on the command line, so the command is written by hand.
@Action("material status", "자료의 상태 바꾸기. 여러 개면 확인을 받는다", confirm: "자료 {materials}의 상태를 {status}(으)로 바꿉니다.",
        done: "자료 {materials}을(를) {status}(으)로 바꿨습니다", phrases: ["자료 분류", "자료 무시"], cli: .manual)
public struct MaterialStatusSet {
    @Arg var course: Course.ID
    @Arg var materials: [Material.ID]
    @Arg var status: MaterialStatus

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            for id in materials { _ = try index(id, in: f.materials, .valueMaterial) }
            for i in f.materials.indices where materials.contains(f.materials[i].id) { f.materials[i].status = status }
        }
    }
}

/// The kind comes before the materials on the command line, so the command is written by hand.
@Action("material kind", "자료의 종류(문제, 제출물, 해설 등) 바꾸기. 여러 개면 확인을 받는다", confirm: "자료 {materials}의 종류를 {kind}(으)로 바꿉니다.",
        done: "자료 {materials}을(를) {kind}(으)로 바꿨습니다", phrases: ["제출물로 표시", "과제 파일 문제 제출물 구분"], cli: .manual)
public struct MaterialKindSet {
    @Arg var course: Course.ID
    @Arg var materials: [Material.ID]
    @Arg var kind: MaterialKind

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            for id in materials { _ = try index(id, in: f.materials, .valueMaterial) }
            for i in f.materials.indices where materials.contains(f.materials[i].id) { f.materials[i].kind = kind }
        }
    }
}

/// Points a material at a file inside the course folder, to replace a missing one.
/// The command reads the file relative to the course folder, so it is written by hand.
@Action("material relink", "사라진 자료를 과목 폴더 안의 다른 파일에 다시 잇기", done: "자료 '{material}'을(를) {file}에 다시 이었습니다",
        phrases: ["사라진 파일 다시 연결", "파일 경로 바뀜"], cli: .manual)
public struct MaterialRelink {
    @Arg var course: Course.ID
    @Arg var material: Material.ID
    /// An absolute path.
    var file: String

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        guard FileManager.default.fileExists(atPath: file) else { throw ActionError.notFound(String(localized: .errorNotFoundFile(file))) }
        do {
            try ctx.edit(course) { f in
                _ = try index(material, in: f.materials, .valueMaterial)
                try store.relink(material, to: URL(filePath: file), in: &f, device: ctx.device, now: ctx.now)
            }
        } catch MaterialFileError.outsideCourseFolder(let name) {
            throw ActionError.rule(String(localized: .errorMaterialOutsideCourse(name)))
        }
    }
}

/// Stops tracking the file. Links to it from sessions, units, quizzes and notes stay, as docs/SPEC.md "파일 추적" asks.
@Action("material untrack", "자료 추적 그만두기. 파일과 연결은 그대로 둔다", done: "자료 '{material}'의 추적을 그만뒀습니다",
        examples: ["folio material untrack EC4207/Seating.pdf"], phrases: ["추적 그만", "자료 목록에서 빼기"])
public struct MaterialUntrack {
    /// 과목
    @Arg var course: Course.ID
    /// 자료
    @Arg var material: Material.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            f.materials.removeAll { $0.id == material }
        }
    }
}

/// Registers new files in the course folder, re-links moved ones, and gives each `Assignments/` folder without one an
/// assignment. Moves and renames nothing. Without a course, every course with a folder.
@Action("material track", "과목 폴더의 새 파일을 등록하고 과제 폴더에 과제를 만든다", done: "자료를 등록했습니다",
        phrases: ["새 파일 등록", "파일 스캔", "자료 반영"], cli: .manual)
public struct MaterialTrack {
    @Arg var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        let courses = try course.map { [$0] } ?? ctx.gist.courseStores().map { try $0.load().model.course.id }
        let today = LocalDate(ctx.now, in: ctx.calendar)
        for course in courses {
            let store = try ctx.store(course)
            let folders = try store.assignmentFolders()
            let ended = try ctx.semester(of: ctx.file(course).course)?.end.map { $0 < today } ?? false
            try ctx.edit(course) { f in
                try store.refreshMaterials(in: &f, device: ctx.device, now: ctx.now)
                for title in AssignmentKind.unmatchedFolders(folders, assignments: f.assignments) {
                    var a = Assignment(device: ctx.device, at: ctx.now, title: title)
                    // A past semester's assignments were all handed in; there is no record saying otherwise.
                    if ended { a.status = .submitted }
                    f.assignments.append(a)
                }
            }
        }
    }
}

/// Copies files in from outside into `folder` (docs/SPEC.md "구조 유지"), registers them, and links them to `session`.
/// `week` puts the week in front of the name, as `Lectures` asks. A file already in this course is linked where it is.
@Action("material import", "바깥 파일을 과목 폴더로 복사해 등록하고 회차에 연결", effect: .creates, done: "파일을 {folder}(으)로 가져왔습니다",
        phrases: ["파일 가져오기", "다운로드한 자료 넣기", "외부 파일 복사"], cli: .manual)
public struct MaterialImport {
    @Arg var course: Course.ID
    /// Absolute paths.
    @Arg var files: [String]
    var folder: String
    var week: Int?
    var session: Session.ID?

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        guard store.contains(folder) else { throw ActionError.rule(String(localized: .errorMaterialImportOutside(folder))) }
        var paths: [String] = []
        for file in files {
            let url = URL(filePath: file)
            if let inside = store.coursePath(of: url) {
                paths.append(inside)
                continue
            }
            let name = week.map { MaterialIntake.lectureName(url.lastPathComponent, week: $0) }
            let planned = try ctx.relative(course, "\(folder)/\(name ?? url.lastPathComponent)")
            if let path = try ctx.io(Change(.added, planned), { try store.importFile(url, into: folder, name: name) }) { paths.append(path) }
        }
        try ctx.edit(course) { f in
            try store.refreshMaterials(in: &f, device: ctx.device, now: ctx.now)
            if let session {
                for m in f.materials where paths.contains(m.path) { f.linkMaterial(m.id, session: session) }
            }
        }
    }
}

/// Renames or moves a file through `moves.jsonl`, keeping its ID and links. `made` is the batch, for `cleanup undo`.
/// The command also prints how to undo the move, so it is written by hand.
@Action("material mv", "자료 파일을 옮기거나 이름 바꾸기. ID와 연결은 그대로", effect: .moves, confirm: "{material}을(를) {to}(으)로 옮깁니다.",
        done: "{material}을(를) {to}(으)로 옮겼습니다", phrases: ["파일 이름 바꾸기", "다른 폴더로", "파일 이름 변경", "파일 옮기기"], cli: .manual)
public struct MaterialMove {
    @Arg var course: Course.ID
    @Arg var material: Material.ID
    /// Course-relative.
    @Arg var to: String

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try ctx.file(course)
        let m = file.materials[try index(material, in: file.materials, .valueMaterial)]
        guard store.contains(to) else { throw ActionError.rule(String(localized: .errorMaterialMoveOutside(to))) }
        let change = Change(.moved, try ctx.relative(course, m.path), to: try ctx.relative(course, to))
        if ctx.dryRun {
            ctx.record(change)
            return
        }
        try ctx.edit(course) { f in
            ctx.made(try store.move(material, to: to, gist: ctx.gist.url, in: &f, device: ctx.device, now: ctx.now))
        }
        ctx.record(change)
    }
}

/// To the Trash, where the user can still put it back, and no longer tracked.
@Action("material rm", "자료 파일을 휴지통으로 옮기고 추적에서 뺀다", discussion: "휴지통에서 되살릴 수 있다.", effect: .removes,
        confirm: "{material}을(를) 휴지통으로 옮깁니다.", done: "{material}을(를) 휴지통으로 옮겼습니다",
        examples: ["folio material rm EC4207/Seating.pdf --dry-run"], phrases: ["파일 삭제", "휴지통"])
public struct MaterialTrash {
    /// 과목
    @Arg var course: Course.ID
    /// 자료
    @Arg var material: Material.ID

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try ctx.file(course)
        let m = file.materials[try index(material, in: file.materials, .valueMaterial)]
        ctx.record(Change(.removed, try ctx.relative(course, m.path)))
        try ctx.edit(course) { f in
            if ctx.dryRun { f.materials.removeAll { $0.id == material } } else { try store.trash(material, in: &f) }
        }
    }
}

/// Moves the user approved, journaled in `moves.jsonl` as one batch (`made`). `course`, when given, has its materials
/// re-linked afterwards.
@Action("cleanup apply", "검토한 계획대로 옮기기. 먼저 GIST 폴더 전체를 백업한다", effect: .moves, confirm: "파일과 폴더 {moves}을(를) 옮깁니다.", done: "파일 {moves}을(를) 옮겼습니다", phrases: ["정리 실행"], cli: .manual)
public struct CleanupApply {
    var moves: [PlannedMove]
    var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        for m in moves { ctx.record(Change(.moved, m.from, to: m.to)) }
        guard !ctx.dryRun else { return }
        ctx.made(try MoveJournal.apply(moves, in: ctx.gist.url, device: ctx.device, now: ctx.now))
        ctx.invalidate()
        if let course { try MaterialTrack(course: course).run(ctx) }
    }
}

@Action("cleanup undo", "cleanup apply나 material mv로 옮긴 묶음을 되돌리기", effect: .moves, confirm: "묶음 {batch}의 이동을 되돌립니다.", done: "묶음 {batch}의 이동을 되돌렸습니다", phrases: ["정리 되돌리기", "이동 취소"], cli: .manual)
public struct CleanupUndo {
    @Arg var batch: MoveBatch.ID
    var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        let records = try MoveJournal.records(in: ctx.gist.url).filter { $0.batch == batch && $0.undoOf == nil }
        guard !records.isEmpty else { throw ActionError.notFound(String(localized: .errorNotFoundMoveBatch("\(batch)"))) }
        for r in records.reversed() { ctx.record(Change(.moved, r.to ?? "", to: r.from)) }
        guard !ctx.dryRun else { return }
        ctx.made(try MoveJournal.undo(batch: batch, in: ctx.gist.url, device: ctx.device, now: ctx.now))
        ctx.invalidate()
        if let course { try MaterialTrack(course: course).run(ctx) }
    }
}

/// One `moves.jsonl` batch, as `cleanup apply` and `material mv` report it.
public enum MoveBatch {
    public typealias ID = UUID
}
