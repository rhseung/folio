import FolioDomain
import FolioStorage
import Foundation

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
        var assignments: [(id: Int, item: LMSAcceptItem)] = []
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
                assignments.append((key.id, item))
            case .file:
                guard let path = item.file else { throw ActionError.rule(String(localized: .errorLmsFileMissing(item.key))) }
                downloads.append(ImportItem(file: path, folder: CourseFolder.lectures.rawValue))
            case .notice:
                break
            }
        }
        for path in downloads.map(\.file) + assignments.flatMap { $0.item.files ?? [] } where !FileManager.default.fileExists(atPath: path)
        {
            throw ActionError.notFound(String(localized: .errorMaterialImportMissing(path)))
        }
        for a in assignments {
            let id = UUID()
            let title = a.item.title ?? ""
            try AssignmentAdd(id: id, course: course, title: title, due: a.item.due, repeats: nil, lms: a.id).run(ctx)
            if let files = a.item.files, !files.isEmpty { try attach(files, to: id, title: title, ctx) }
        }
        if !downloads.isEmpty { try MaterialImport(course: course, items: downloads).run(ctx) }
        try ctx.editSettings { $0.lms.mark(keys, handled: true) }
    }

    // 과제 폴더 안의 이름은 바꾸지 않는다. 같은 이름이 있으면 `importFile`이 ` 2`를 붙인다.
    private func attach(_ files: [String], to assignment: UUID, title: String, _ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        // 폴더는 저장된 과제에서 읽는다. dry-run에서는 과제가 저장되지 않아 같은 제목으로 짓는다.
        let stored = try ctx.file(course).assignments.first { $0.id == assignment }
        let folder = AssignmentFiles.path(of: stored ?? Assignment(device: ctx.device, at: ctx.now, title: title))
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
