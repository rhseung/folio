import FolioDomain
import FolioStorage
import Foundation

@Action(
    "lms accept", "LMS 제안을 과목에 받기. 과제는 과제로 더하고, 받은 파일은 Lectures로 가져오고, 모두 제안함에서 숨긴다",
    discussion: """
        항목 파일은 [{"key":"assignment:139950","classroom":27967,"title":"HW5","due":"2026-11-20T14:55:00Z","files":["/tmp/hw5.pdf"]}, {"key":"file:139200","classroom":27967,"file":"/tmp/05_Matchings.pdf"}, {"key":"notice:23464"}] 꼴이다.
        과제의 files는 과제 페이지에서 받은 첨부이고, 과제 폴더(Assignments/<과제>)에 원래 이름으로 들어가 문제 파일이 된다.
        과목을 주면 항목의 강의실(classroom)에 그 과목을 기억한다. 과목을 빼면 강의실마다 기억한 과목에 받는다.
        이미 받은 과제의 새 첨부는 {"key":"attachments:139950:2","files":["/tmp/hw5-b.pdf"]}이고, 그 과제의 폴더에 원래 이름으로 들어간다.
        files가 비면(뷰어 전용이라 내려받지 못함) 받지 않고 제안에서 숨기기만 한다. 과제의 attachmentCount는 받을 때의 첨부 수이고, 그 수의 새 첨부 키를 함께 숨긴다.
        """,
    effect: .creates, done: "LMS 항목을 받았습니다",
    phrases: ["LMS 과제 추가", "LMS 자료 받기", "LMS 제안 모두 추가", "기억한 과목에 모두 받기"])
public struct LMSAccept {
    /// 과목. 빼면 항목의 강의실마다 기억한 과목
    @Arg var course: Course.ID?
    /// 받을 항목
    @FromFile("items.json") var items: [LMSAcceptItem]

    public func run(_ ctx: ActionContext) throws {
        guard !items.isEmpty else { throw ActionError.input(String(localized: .errorLmsNoKeys)) }
        let lms = try ctx.settings().lms
        var byCourse: [(course: Course.ID, items: [(key: LMSKey, item: LMSAcceptItem)])] = []
        for item in items {
            guard let key = LMSKey(item.key) else { throw ActionError.input(String(localized: .errorLmsKey(item.key))) }
            guard let target = try target(of: item, lms) else {
                throw ActionError.input(String(localized: .errorLmsNoCourse(item.key)))
            }
            if let i = byCourse.firstIndex(where: { $0.course == target }) {
                byCourse[i].items.append((key, item))
            } else {
                byCourse.append((target, [(key, item)]))
            }
        }
        let planned = try byCourse.map { try plan($0.course, $0.items, ctx) }
        let paths = planned.flatMap {
            $0.downloads.map(\.file) + $0.assignments.flatMap { $0.item.files ?? [] } + $0.attachments.flatMap(\.files)
        }
        for path in paths where !FileManager.default.fileExists(atPath: path) {
            throw ActionError.notFound(String(localized: .errorMaterialImportMissing(path)))
        }
        for p in planned {
            for a in p.assignments {
                let id = UUID()
                let title = a.item.title ?? ""
                try AssignmentAdd(id: id, course: p.course, title: title, due: a.item.due, repeats: nil, lms: a.id).run(ctx)
                if let files = a.item.files, !files.isEmpty { try attach(files, to: id, title: title, in: p.course, ctx) }
            }
            for a in p.attachments { try attach(a.files, to: a.assignment.id, title: a.assignment.title, in: p.course, ctx) }
            if !p.downloads.isEmpty { try MaterialImport(course: p.course, items: p.downloads).run(ctx) }
        }
        let attachmentKeys = byCourse.flatMap(\.items).compactMap { k, item -> LMSKey? in
            guard k.kind == .assignment, let n = item.attachmentCount, n > 0 else { return nil }
            return LMSKey(kind: .attachments, id: k.id, stamp: n)
        }
        let keys = byCourse.flatMap { $0.items.map(\.key) } + attachmentKeys
        let remembered = course.map { c in Set(items.compactMap(\.classroom)).map { ($0, c) } } ?? []
        try ctx.editSettings { s in
            s.lms.mark(keys, handled: true)
            for (classroom, c) in remembered { s.lms.remember(LMSRoom(course: c), for: classroom) }
        }
    }

    private func target(of item: LMSAcceptItem, _ lms: LMSSettings) throws -> Course.ID? {
        if let course { return course }
        return item.classroom.flatMap(lms.course(of:))
    }

    private struct Plan {
        var course: Course.ID
        var assignments: [(id: Int, item: LMSAcceptItem)] = []
        var downloads: [ImportItem] = []
        var attachments: [(assignment: Assignment, files: [String])] = []
    }

    // 쓰기 전에 모든 과목의 항목을 검사해, 하나가 막히면 아무것도 쓰지 않는다.
    private func plan(_ course: Course.ID, _ items: [(key: LMSKey, item: LMSAcceptItem)], _ ctx: ActionContext) throws -> Plan {
        let file = try ctx.file(course)
        var plan = Plan(course: course)
        for (key, item) in items {
            switch key.kind {
            case .assignment:
                guard let title = item.title, !title.isEmpty else { throw ActionError.rule(String(localized: .errorAssignmentTitleEmpty)) }
                if let same = file.assignments.first(where: { $0.lmsId == key.id }) {
                    throw ActionError.rule(String(localized: .errorLmsAssignmentAdded(same.title)))
                }
                plan.assignments.append((key.id, item))
            case .file:
                guard let path = item.file else { throw ActionError.rule(String(localized: .errorLmsFileMissing(item.key))) }
                plan.downloads.append(ImportItem(file: path, folder: CourseFolder.lectures.rawValue))
            case .notice:
                break
            case .attachments:
                guard let same = file.assignments.first(where: { $0.lmsId == key.id }) else {
                    throw ActionError.notFound(String(localized: .errorLmsAssignmentMissing(item.key)))
                }
                // 받을 첨부가 모두 뷰어 전용이면 내려받은 파일이 없다. 실패시키면 그 제안을 치울 길이 무시뿐이라 숨기기만 한다.
                if let files = item.files, !files.isEmpty { plan.attachments.append((same, files)) }
            case .submitted, .unsubmitted, .due:
                throw ActionError.input(String(localized: .errorLmsKey(item.key)))
            }
        }
        return plan
    }

    // 과제 폴더 안의 이름은 바꾸지 않는다. 같은 이름이 있으면 `importFile`이 ` 2`를 붙인다.
    private func attach(_ files: [String], to assignment: UUID, title: String, in course: Course.ID, _ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        // 폴더는 저장된 과제에서 읽는다. dry-run에서는 과제가 저장되지 않아 같은 제목으로 짓는다.
        let stored = try ctx.file(course).assignments.first { $0.id == assignment }
        let folder = AssignmentFiles.path(
            of: stored ?? Assignment(device: ctx.device, at: ctx.now, title: title), kinds: try ctx.settings().assignmentKindTable)
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
