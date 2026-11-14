import FolioDomain
import FolioStorage
import Foundation

@Action(
    "material write", "텍스트 자료(.tex, 코드, .txt 등) 파일 전체를 바꾸기", done: "자료 '{material}'을(를) 썼습니다",
    phrases: ["tex 수정", "코드 파일 고치기", "텍스트 파일 쓰기"], cli: .manual(reason: "--expect의 해시를 지금 파일과 비교한 뒤 그 원문을 expected로 넘긴다"))
public struct MaterialWrite {
    @Arg var course: Course.ID
    @Arg var material: Material.ID
    var text: String
    /// What the file held when it was read. A different file means another device or app changed it since.
    var expected: String?

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try ctx.file(course)
        let m = file.materials[try index(material, in: file.materials, .valueMaterial)]
        guard !m.isFolder, MaterialFormat(path: m.path).isText else {
            throw ActionError.rule(String(localized: .errorMaterialNotText(m.path)))
        }
        if let expected, try Self.read(store, m.path) != expected {
            throw ActionError.conflict(String(localized: .errorMaterialChanged(m.path)))
        }
        if expected == nil { _ = try Self.read(store, m.path) }
        try ctx.io(Change(.changed, try ctx.relative(course, m.path))) { try store.writeText(m.path, text: text) }
        guard !ctx.dryRun else { return }
        try ctx.edit(course) { f in try store.rehash(material, in: &f, device: ctx.device, now: ctx.now) }
    }
}

extension MaterialWrite {
    // 다른 인코딩의 파일을 UTF-8로 다시 쓰면 그 파일을 만든 프로그램이 읽지 못할 수 있으므로, UTF-8 파일만 바꾼다.
    static func read(_ store: CourseStore, _ path: String) throws -> String {
        do {
            return try store.readText(path)
        } catch StorageError.notUTF8 {
            throw ActionError.rule(String(localized: .errorMaterialNotUtf8(path)))
        }
    }
}

@Action(
    "material new", "과제·시험 폴더나 Study, Archive에 새 텍스트 파일(.tex, 코드, .txt 등) 만들기. .tex는 바로 빌드되는 문서 틀로 시작한다",
    effect: .creates, done: "{folder}/{name}을(를) 만들었습니다",
    examples: ["folio material new EC4207 Assignments/HW03 hw3.tex", "folio material new EC4207 Study 풀이.py --dry-run"],
    phrases: ["새 파일", "tex 파일 만들기", "과제 tex 만들기", "새 코드 파일"])
public struct MaterialNew {
    /// 과목
    @Arg var course: Course.ID
    /// 과목 폴더 기준 폴더. 예: Assignments/HW04, Exams/중간고사, Study
    @Arg var folder: String
    /// 확장자까지 쓴 파일 이름. 예: hw4.tex
    @Arg var name: String

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try ctx.file(course)
        let folder = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard NewMaterialFile.accepts(folder: folder) else { throw ActionError.rule(String(localized: .errorMaterialNewPlace(folder))) }
        let places = NewMaterialFile.places(
            assignments: file.assignments, exams: file.exams, assignmentFolders: try store.assignmentFolders())
        guard NewMaterialFile.accepts(folder: folder, places: places) else {
            throw ActionError.rule(String(localized: .errorMaterialNewNoItem(folder)))
        }
        guard NewMaterialFile.isFileName(name) else { throw ActionError.rule(String(localized: .errorMaterialNewName(name))) }
        guard MaterialFormat(path: name).isText else { throw ActionError.rule(String(localized: .errorMaterialNewFormat(name))) }

        let path = "\(folder)/\(name)"
        // 추적은 코드 프로젝트를 폴더 하나로 보므로, 그 안에 만든 파일에는 열 행이 없다. 추적 목록은 `git init`이나 아직
        // 추적하지 않은 프로젝트를 늦게 따라가므로 디스크에서 읽는다.
        if let project = store.codeProject(containing: folder)
            ?? file.materials.first(where: { $0.isFolder && path.hasPrefix($0.path + "/") })?.path
        {
            throw ActionError.rule(String(localized: .errorMaterialNewInFolder(project)))
        }
        guard !FileManager.default.fileExists(atPath: store.fileURL(path).path) else {
            throw ActionError.conflict(String(localized: .errorMaterialNewTaken(path)))
        }
        try ctx.io(Change(.added, try ctx.relative(course, path))) { try store.createText(path, text: NewMaterialFile.text(for: name)) }

        guard !ctx.dryRun else { return }
        try ctx.edit(course) { f in try store.refreshMaterials(in: &f, device: ctx.device, now: ctx.now) }
        guard let m = try ctx.file(course).materials.first(where: { $0.path == path }) else {
            throw ActionError.rule(String(localized: .errorMaterialNewUntracked(path)))
        }
        ctx.made(m.id)
    }
}

@Action(
    "material build", "LaTeX 자료(.tex)를 Tectonic으로 PDF로 만들어 옆에 같은 이름으로 둔다", done: "'{material}'을(를) PDF로 만들었습니다",
    phrases: ["tex 컴파일", "latex 빌드", "PDF 만들기"])
public struct MaterialBuild {
    /// 과목
    @Arg var course: Course.ID
    /// .tex 자료
    @Arg var material: Material.ID
    /// 앱이 이 자료를 Tectonic으로 빌드해 둔 PDF. 빌드 출력 폴더 밖의 파일은 받지 않는다. 빼면 직접 빌드한다
    @Hidden var pdf: String?
    /// 같은 이름의 PDF가 Folio가 만든 것이 아니어도 바꾼다
    var overwrite = false

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try ctx.file(course)
        let m = file.materials[try index(material, in: file.materials, .valueMaterial)]
        guard let built = MaterialFormat.builtPDF(of: m.path) else {
            throw ActionError.rule(String(localized: .errorMaterialNotTex(m.path)))
        }

        let existing = file.materials.builtPDF(of: m)
        let target = existing?.path ?? built
        let exists = FileManager.default.fileExists(atPath: store.fileURL(target).path)
        var ours = false
        if exists, let made = existing?.builtHash { ours = try made == store.hash(target) }
        if exists, !ours, !overwrite {
            throw ActionError.conflict(String(localized: .errorBuildWouldReplace(target)))
        }

        let change = Change(exists ? .changed : .added, try ctx.relative(course, target))
        guard !ctx.dryRun else {
            ctx.record(change)
            return
        }

        let source = store.fileURL(m.path)
        let output = try pdf.map { try Self.output($0, of: source) } ?? Self.compile(source, ctx)
        try ctx.io(change) { try store.replaceFile(target, with: output, keepOld: exists && !ours) }

        try ctx.edit(course) { f in
            try store.refreshMaterials(in: &f, device: ctx.device, now: ctx.now)
            if let i = f.materials.firstIndex(where: { $0.path == target }) {
                try store.rehash(f.materials[i].id, in: &f, device: ctx.device, now: ctx.now)
                f.materials[i].builtHash = f.materials[i].hash
            }
        }
    }

    // 이 파일은 추적된 PDF의 자리를 차지하고 해시가 빌드한 것으로 표시되어, 다음 빌드가 묻지 않고 바꾼다. 그래서
    // 넘겨받은 다른 파일이 이 방법으로 과목 PDF를 덮어쓰지 못하게 한다.
    static func output(_ path: String, of source: URL) throws -> URL {
        let folder = TexOutput.folder(for: source).resolvingSymlinksInPath().path + "/"
        let url = URL(filePath: path).resolvingSymlinksInPath()
        guard url.path.hasPrefix(folder) else { throw ActionError.rule(String(localized: .errorBuildOutputElsewhere(path))) }
        return url
    }

    static func compile(_ source: URL, _ ctx: ActionContext) throws -> URL {
        let build = try TexEngine.shared.compile(source, into: TexEngine.outputFolder(for: source), at: ctx.now, calendar: ctx.calendar)
        guard let pdf = build.pdf else {
            throw ActionError.rule(String(localized: .errorTexFailed(build.errors.map(\.description).joined(separator: "\n"))))
        }
        return pdf
    }
}

@Action(
    "note build", "LaTeX 노트(.tex)를 Tectonic으로 PDF로 만들어 Study에 둔다", done: "노트 '{note}'을(를) PDF로 만들었습니다",
    phrases: ["tex 노트 컴파일", "노트 PDF 만들기"])
public struct NoteBuild {
    /// 과목
    @Arg var course: Course.ID
    /// .tex 노트
    @Arg var note: Note.Path
    /// 앱이 이 노트를 Tectonic으로 빌드해 둔 PDF. 빌드 출력 폴더 밖의 파일은 받지 않는다. 빼면 직접 빌드한다
    @Hidden var pdf: String?
    /// 그 자리의 PDF가 이 노트를 빌드한 것이 아니어도 바꾼다
    var overwrite = false

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try FolioActions.note(ctx, course: course, path: note)
        guard file.format == .tex else { throw ActionError.rule(String(localized: .errorMaterialNotTex(note))) }

        let target = store.exportPath(of: file)
        let exists = FileManager.default.fileExists(atPath: store.fileURL(target).path)
        // 이 빌드의 PDF를 남의 PDF와 구분하는 해시를 항목이 가진다. 항목이 없으면 이후 빌드마다 방금 만든 PDF를 묻는다.
        guard let entry = try ctx.file(course).notes.first(where: { $0.id == file.meta.id }) else {
            throw ActionError.rule(String(localized: .errorNoteBuildNoEntry(note)))
        }
        var ours = false
        if exists, let made = entry.builtHash { ours = try made == store.hash(target) }
        if exists, !ours, !overwrite {
            throw ActionError.conflict(String(localized: .errorBuildWouldReplace(target)))
        }

        let change = Change(exists ? .changed : .added, try ctx.relative(course, target))
        guard !ctx.dryRun else {
            ctx.record(change)
            return
        }

        let built = try pdf.map { try MaterialBuild.output($0, of: file.url) } ?? MaterialBuild.compile(file.url, ctx)
        try ctx.io(change) {
            try FileManager.default.createDirectory(
                at: store.fileURL(target).deletingLastPathComponent(), withIntermediateDirectories: true)
            try store.replaceFile(target, with: built, keepOld: exists && !ours)
        }

        let hash = try store.hash(target)
        try ctx.edit(course) { f in
            if let i = f.notes.firstIndex(where: { $0.id == entry.id }) { f.notes[i].builtHash = hash }
            try store.refreshMaterials(in: &f, device: ctx.device, now: ctx.now)
            if let i = f.materials.firstIndex(where: { $0.path == target }) {
                try store.rehash(f.materials[i].id, in: &f, device: ctx.device, now: ctx.now)
            }
        }
    }
}
