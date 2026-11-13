import FolioDomain
import FolioStorage
import Foundation

@Action("material link", "자료를 회차에 연결하거나 떼기", done: "자료 '{material}'과(와) 회차 '{session}'의 연결을 바꿨습니다",
        phrases: ["자료 수업 연결", "슬라이드 회차에 붙이기"], cli: .manual(reason: "--pages 3-12 한 옵션을 firstPage와 lastPage 두 필드로 나눈다"))
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

@Action("material link-exam", "자료를 시험에 연결하거나 떼기. 시험 폴더 밖의 자료(Study, Inherited)를 그 시험에 모은다",
        done: "자료 '{material}'과(와) 시험 '{exam}'의 연결을 바꿨습니다",
        examples: ["folio material link-exam EC4207/Study/Problems.pdf 중간고사", "folio material link-exam EC4207/Study/Problems.pdf 중간고사 --off"],
        phrases: ["자료 시험 연결", "시험 대비 자료 연결", "족보 시험에 붙이기"])
public struct MaterialLinkExam {
    /// 과목
    @Arg var course: Course.ID
    /// 자료
    @Arg var material: Material.ID
    /// 같은 과목의 시험
    @Arg var exam: Exam.ID
    /// 연결 떼기
    @Off("off") var linked = true

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            _ = try index(exam, in: f.exams, .valueExam)
            f.setMaterial(material, exam: exam, linked: linked)
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

// The status comes before the materials on the command line, so it is declared first.
@Action("material status", "자료의 상태 바꾸기. 여러 개면 확인을 받는다", confirm: "자료 {materials}의 상태를 {status}(으)로 바꿉니다.",
        done: "자료 {materials}을(를) {status}(으)로 바꿨습니다",
        examples: ["folio material status ignored EC4207/Seating.pdf", "folio material status classified EC4207/Problems.pdf Guideline.pdf"],
        phrases: ["자료 분류", "자료 무시"])
public struct MaterialStatusSet {
    @Arg var course: Course.ID
    /// 상태
    @Arg var status: MaterialStatus
    /// 자료
    @Arg var materials: [Material.ID]

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            for id in materials { _ = try index(id, in: f.materials, .valueMaterial) }
            for i in f.materials.indices where materials.contains(f.materials[i].id) { f.materials[i].status = status }
        }
    }
}

// The kind comes before the materials on the command line, so it is declared first.
@Action("material kind", "자료의 종류(문제, 제출물, 해설 등) 바꾸기. 여러 개면 확인을 받는다",
        discussion: "과제 폴더의 파일은 종류가 없으면 이름으로 짐작한다(HW3-이름.pdf는 제출물, 나머지는 문제).",
        confirm: "자료 {materials}의 종류를 {kind}(으)로 바꿉니다.", done: "자료 {materials}을(를) {kind}(으)로 바꿨습니다",
        examples: ["folio material kind submission EC4207/26h3.pdf", "folio material kind problem EC4207/26h3.pdf"],
        phrases: ["제출물로 표시", "과제 파일 문제 제출물 구분"])
public struct MaterialKindSet {
    @Arg var course: Course.ID
    /// 종류
    @Arg var kind: MaterialKind
    /// 자료
    @Arg var materials: [Material.ID]

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            for id in materials { _ = try index(id, in: f.materials, .valueMaterial) }
            for i in f.materials.indices where materials.contains(f.materials[i].id) { f.materials[i].kind = kind }
        }
    }
}

@Action("material relink", "사라진 자료를 과목 폴더 안의 다른 파일에 다시 잇기", done: "자료 '{material}'을(를) {file}에 다시 이었습니다",
        phrases: ["사라진 파일 다시 연결", "파일 경로 바뀜"], cli: .manual(reason: "상대 경로를 명령을 실행한 폴더가 아니라 과목 폴더 기준으로 푼다"))
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

@Action("material untrack", "자료 추적 그만두기. 파일은 그대로 두고 회차, 문제 묶음, 과제의 연결은 푼다", done: "자료 '{material}'의 추적을 그만뒀습니다",
        examples: ["folio material untrack EC4207/Seating.pdf"], phrases: ["추적 그만", "자료 목록에서 빼기"])
public struct MaterialUntrack {
    /// 과목
    @Arg var course: Course.ID
    /// 자료
    @Arg var material: Material.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            try f.remove(Material.self, material)
        }
    }
}

/// Files moved in Finder are re-linked rather than registered again.
@Action("material track", "과목 폴더의 새 파일을 등록하고 과제 폴더에 과제를 만든다",
        discussion: "옮기거나 이름을 바꾸지 않는다. 과목을 빼면 모든 과목에 한다. 지난 학기의 새 과제는 제출함으로 둔다.", done: "자료를 등록했습니다",
        examples: ["folio material track EC4207", "folio material track --dry-run"],
        phrases: ["새 파일 등록", "파일 스캔", "자료 반영"])
public struct MaterialTrack {
    /// 과목. 빼면 모든 과목
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

public struct ImportItem: Codable, Sendable, Hashable {
    /// Absolute path.
    public var file: String
    /// Course-relative.
    public var folder: String
    public var session: Session.ID?
    /// A lecture's sections as the add sheet approved them (#321); nil leaves the file unsplit.
    public var sections: [LectureCut]?

    public init(file: String, folder: String, session: Session.ID? = nil, sections: [LectureCut]? = nil) {
        (self.file, self.folder, self.session, self.sections) = (file, folder, session, sections)
    }
}

/// Copies files in from outside, each into its own folder, registers them, and links each to its session. A file put
/// in `Lectures` for a session takes the session's week in front of its name. A file already in this course is linked
/// where it is. Every item is checked before the first copy, so one that can't go in stops them all.
@Action("material import", "바깥 파일을 과목 폴더로 복사해 등록하고 회차에 연결", effect: .creates, done: "파일 {items}을(를) 가져왔습니다",
        phrases: ["파일 가져오기", "다운로드한 자료 넣기", "외부 파일 복사"], cli: .manual(reason: "파일마다 --folder와 --session을 붙여 가져올 항목(ImportItem)을 만든다"))
public struct MaterialImport {
    @Arg var course: Course.ID
    var items: [ImportItem]

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try ctx.file(course)
        for item in items {
            guard store.contains(item.folder) else { throw ActionError.rule(String(localized: .errorMaterialImportOutside(item.folder))) }
            guard FileManager.default.fileExists(atPath: item.file) else {
                throw ActionError.notFound(String(localized: .errorMaterialImportMissing(item.file)))
            }
            if let session = item.session { _ = try index(session, in: file.sessions, .valueSession) }
            if let cuts = item.sections { try checkCuts(cuts, in: file) }
        }

        var linked: [(path: String, item: ImportItem)] = []
        for item in items {
            let url = URL(filePath: item.file)
            if let inside = store.coursePath(of: url) {
                linked.append((inside, item))
                continue
            }
            let name = MaterialIntake.name(url.lastPathComponent, in: item.folder, session: file.sessions.first { $0.id == item.session })
            let planned = try ctx.relative(course, "\(item.folder)/\(name)")
            if let path = try ctx.io(Change(.added, planned), { try store.importFile(url, into: item.folder, name: name) }) {
                linked.append((path, item))
            }
        }

        try ctx.edit(course) { f in
            try store.refreshMaterials(in: &f, device: ctx.device, now: ctx.now)
            for (path, item) in linked {
                guard let m = f.materials.first(where: { $0.path == path }) else { continue }
                if let session = item.session { f.linkMaterial(m.id, session: session) }
                if let cuts = item.sections { f.split(m.id, into: cuts, device: ctx.device, now: ctx.now) }
            }
        }
    }
}

/// `made` is the `moves.jsonl` batch, for `cleanup undo`.
@Action("material mv", "자료 파일을 옮기거나 이름 바꾸기. ID와 연결은 그대로", discussion: "moves.jsonl에 남겨서 folio cleanup undo로 되돌릴 수 있다.",
        effect: .moves, confirm: "{material}을(를) {to}(으)로 옮깁니다.", done: "{material}을(를) {to}(으)로 옮겼습니다",
        examples: ["folio material mv EC4207/Seating.pdf Exams/Midterm/자리.pdf --dry-run"],
        phrases: ["파일 이름 바꾸기", "다른 폴더로", "파일 이름 변경", "파일 옮기기"], undoable: true)
public struct MaterialMove {
    @Arg var course: Course.ID
    /// 자료
    @Arg var material: Material.ID
    /// 새 경로. 과목 폴더 기준
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
            if ctx.dryRun { try f.remove(Material.self, material) } else { try store.trash(material, in: &f) }
        }
    }
}

/// Moves the user approved, journaled in `moves.jsonl` as one batch (`made`). `course`, when given, has its materials
/// re-linked afterwards.
@Action("cleanup apply", "검토한 계획대로 옮기기. 먼저 GIST 폴더 전체를 백업한다", effect: .moves, confirm: "파일과 폴더 {moves}을(를) 옮깁니다.", done: "파일 {moves}을(를) 옮겼습니다", phrases: ["정리 실행"],
        cli: .manual(reason: "계획 파일을 읽어 검토 표시된 이동을 거르고, 확인을 받은 뒤 GIST 폴더를 --backup에 백업하고 나서 실행한다"), undoable: true)
public struct CleanupApply {
    var moves: [PlannedMove]
    var removals: [String] = []
    var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        for m in moves { ctx.record(Change(.moved, m.from, to: m.to)) }
        for r in removals { ctx.record(Change(.removed, r + "/")) }
        guard !ctx.dryRun else { return }
        ctx.made(try MoveJournal.apply(moves, removing: removals, in: ctx.gist.url, device: ctx.device, now: ctx.now))
        ctx.invalidate()
        if let course { try MaterialTrack(course: course).run(ctx) }
        try annotate(ctx)
    }

    /// Writes each moved file's exam link and kind. Tracking runs first so the file's material already has its new
    /// path (and keeps its id when it was tracked before). Undoing the moves leaves these on the materials.
    func annotate(_ ctx: ActionContext) throws {
        let annotated = moves.filter { $0.exam != nil || $0.kind != nil }
        guard !annotated.isEmpty else { return }
        for store in try ctx.gist.courseStores() {
            let base = ctx.relative(store.url) + "/"
            let mine = annotated.filter { $0.to.hasPrefix(base) }
            guard !mine.isEmpty, let id = try? store.load().model.course.id else { continue }
            if id != course { try MaterialTrack(course: id).run(ctx) }
            try ctx.edit(id) { f in
                for move in mine {
                    guard let m = f.materials.firstIndex(where: { $0.path == String(move.to.dropFirst(base.count)) }) else { continue }
                    if let kind = move.kind { f.materials[m].kind = kind }
                    guard let folder = move.exam else { continue }
                    // The plan read the exams earlier; one renamed or deleted since can't be linked.
                    if let exam = f.exams.first(where: { $0.folder == folder }) {
                        f.setMaterial(f.materials[m].id, exam: exam.id, linked: true)
                    } else {
                        ctx.note(String(localized: .noteCleanupUnlinked(move.to, folder)))
                    }
                }
            }
        }
    }
}

@Action("cleanup undo", "cleanup apply, material mv, note retitle, note mv, recording retitle로 옮긴 묶음을 되돌리기", effect: .moves, confirm: "묶음 {batch}의 이동을 되돌립니다.", done: "묶음 {batch}의 이동을 되돌렸습니다",
        examples: ["folio cleanup undo 6A1F0C2E-3B4D-4E5F-8A9B-0C1D2E3F4A5B --dry-run"], phrases: ["정리 되돌리기", "이동 취소"])
public struct CleanupUndo {
    /// 묶음 ID
    @Arg var batch: MoveBatch.ID
    // The app's course page passes its course, to re-link its materials after the undo.
    @Hidden var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        let records = try MoveJournal.records(in: ctx.gist.url).filter { $0.batch == batch && $0.undoOf == nil }
        guard !records.isEmpty else { throw ActionError.notFound(String(localized: .errorNotFoundMoveBatch("\(batch)"))) }
        for r in records.reversed() { ctx.record(Change(.moved, r.to ?? "", to: r.from)) }
        let moves = records.reversed().compactMap { r in r.op == .move ? r.to.flatMap { to in r.from.map { PlannedMove(from: to, to: $0) } } : nil }
        // Notes `note retitle` or `note mv` renamed take their old titles back, in headings and links too.
        let undone = try NoteTitles.follow(moves, ctx, move: { try MoveJournal.undo(batch: batch, in: ctx.gist.url, device: ctx.device, now: ctx.now) })
        // Recordings `recording retitle` renamed point at their old names again.
        try RecordingFiles.follow(moves, ctx)
        guard let undone else { return }
        ctx.made(undone)
        ctx.invalidate()
        if let course { try MaterialTrack(course: course).run(ctx) }
    }
}

/// One `moves.jsonl` batch, as `cleanup apply` and `material mv` report it.
public enum MoveBatch {
    public typealias ID = UUID
}
