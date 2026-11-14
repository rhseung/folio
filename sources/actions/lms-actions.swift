import FolioDomain
import FolioStorage
import Foundation

@Action(
    "lms seen", "처음 본 LMS 강의실을 기록하고 지금 있는 항목을 제안함에서 숨기기",
    discussion: """
        강의실을 처음 볼 때 그 강의실에 이미 있는 파일과 공지를 --items로 넘겨, 그 뒤에 올라온 것만 제안한다.
        강의실을 과목에 잇지 않는다. 제안은 받을 때마다 과목을 고른다.
        """,
    done: "LMS 강의실 {classrooms}을(를) 기록했습니다",
    examples: ["folio lms seen 27967 28011 --items file:139109 --items notice:23464"],
    phrases: ["LMS 강의실 기록", "LMS 새 강의실"])
public struct LMSSeen {
    /// LMS 강의실 번호(course/view.php?id=)
    @Arg var classrooms: [Int]
    /// 제안함에서 숨길 항목. file:139109, notice:23464 꼴
    var items: [String] = []

    public func run(_ ctx: ActionContext) throws {
        guard !classrooms.isEmpty else { throw ActionError.input(String(localized: .errorLmsNoClassrooms)) }
        let keys = try items.map { text in
            guard let key = LMSKey(text) else { throw ActionError.input(String(localized: .errorLmsKey(text))) }
            return key
        }
        try ctx.editSettings { s in
            s.lms.know(classrooms)
            s.lms.mark(keys, handled: true)
        }
    }
}

@Action(
    "lms mark", "LMS 항목을 제안함에서 숨기기, --off면 다시 제안하기",
    done: "LMS 항목 {keys}을(를) 표시했습니다",
    examples: ["folio lms mark notice:23464 file:139109", "folio lms mark notice:23464 --off"],
    phrases: ["LMS 제안 무시", "LMS 공지 숨기기"])
public struct LMSMark {
    /// 항목. assignment:139941, file:139109, notice:23464 꼴
    @Arg var keys: [String]
    /// 다시 제안하기
    @Off("off") var handled = true

    public func run(_ ctx: ActionContext) throws {
        guard !keys.isEmpty else { throw ActionError.input(String(localized: .errorLmsNoKeys)) }
        let parsed = try keys.map { text in
            guard let key = LMSKey(text) else { throw ActionError.input(String(localized: .errorLmsKey(text))) }
            return key
        }
        try ctx.editSettings { $0.lms.mark(parsed, handled: handled) }
    }
}

public struct LMSAcceptItem: Codable, Sendable, Hashable {
    public var key: String
    public var title: String?
    public var due: Date?
    public var file: String?
    public var files: [String]?

    public init(key: String, title: String? = nil, due: Date? = nil, file: String? = nil, files: [String]? = nil) {
        (self.key, self.title, self.due, self.file, self.files) = (key, title, due, file, files)
    }
}

@Action(
    "lms accept", "LMS 제안을 과목에 받기. 과제는 과제로 더하고, 받은 파일은 Lectures로 가져오고, 모두 제안함에서 숨긴다",
    discussion: """
        항목 파일은 [{"key":"assignment:139950","title":"HW5","due":"2026-11-20T14:55:00Z","files":["/tmp/hw5.pdf"]}, {"key":"file:139200","file":"/tmp/05_Matchings.pdf"}, {"key":"notice:23464"}] 꼴이다.
        과제의 files는 과제 페이지에서 받은 첨부이고, 과제 폴더(Assignments/<과제>)에 원래 이름으로 들어가 문제 파일이 된다.
        """,
    effect: .creates, done: "{course}에 LMS 항목을 받았습니다",
    phrases: ["LMS 과제 추가", "LMS 자료 받기", "LMS 제안 모두 추가"])
public struct LMSAccept {
    /// 과목
    @Arg var course: Course.ID
    /// 받을 항목
    @FromFile("items.json") var items: [LMSAcceptItem]

    public func run(_ ctx: ActionContext) throws {
        guard !items.isEmpty else { throw ActionError.input(String(localized: .errorLmsNoKeys)) }
        let file = try ctx.file(course)
        var keys: [LMSKey] = []
        var assignments: [Incoming] = []
        var downloads: [ImportItem] = []
        for item in items {
            guard let key = LMSKey(item.key) else { throw ActionError.input(String(localized: .errorLmsKey(item.key))) }
            keys.append(key)
            switch key.kind {
            case .assignment:
                guard let title = item.title, !title.isEmpty else { throw ActionError.rule(String(localized: .errorAssignmentTitleEmpty)) }
                if let same = file.assignments.first(where: { $0.lmsId == key.id }) {
                    throw ActionError.rule(String(localized: .errorLmsAssignmentAdded(same.title)))
                }
                assignments.append(Incoming(id: key.id, title: title, due: item.due, files: item.files ?? []))
            case .file:
                guard let path = item.file else { throw ActionError.rule(String(localized: .errorLmsFileMissing(item.key))) }
                downloads.append(ImportItem(file: path, folder: CourseFolder.lectures.rawValue))
            case .notice:
                break
            }
        }
        for path in downloads.map(\.file) + assignments.flatMap(\.files) where !FileManager.default.fileExists(atPath: path) {
            throw ActionError.notFound(String(localized: .errorMaterialImportMissing(path)))
        }
        for a in assignments {
            let id = UUID()
            try AssignmentAdd(id: id, course: course, title: a.title, due: a.due, repeats: nil, lms: a.id).run(ctx)
            if !a.files.isEmpty { try attach(a.files, to: id, title: a.title, ctx) }
        }
        if !downloads.isEmpty { try MaterialImport(course: course, items: downloads).run(ctx) }
        try ctx.editSettings { $0.lms.mark(keys, handled: true) }
    }

    private struct Incoming {
        var id: Int
        var title: String
        var due: Date?
        var files: [String]
    }

    // 과제 폴더 안의 이름은 바꾸지 않는다. 같은 이름이 있으면 `importFile`이 ` 2`를 붙인다.
    private func attach(_ files: [String], to assignment: UUID, title: String, _ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let folder = AssignmentFiles.path(of: Assignment(device: ctx.device, at: ctx.now, title: title))
        var paths: [String] = []
        for file in files {
            let url = URL(filePath: file)
            let planned = try ctx.relative(course, "\(folder)/\(url.lastPathComponent)")
            if let path = try ctx.io(Change(.added, planned), { try store.importFile(url, into: folder) }) { paths.append(path) }
        }
        guard !paths.isEmpty else { return }
        try ctx.edit(course) { f in
            try store.refreshMaterials(in: &f, device: ctx.device, now: ctx.now)
            let added = paths.compactMap { path in f.materials.firstIndex { $0.path == path } }
            for i in added { f.materials[i].kind = .problem }
            if let a = f.assignments.firstIndex(where: { $0.id == assignment }), f.assignments[a].problemMaterialId == nil,
                let first = added.first
            {
                f.assignments[a].problemMaterialId = f.materials[first].id
            }
        }
    }
}
