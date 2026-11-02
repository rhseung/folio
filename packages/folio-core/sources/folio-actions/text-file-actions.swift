import FolioDomain
import FolioStorage
import Foundation

/// The command reads the text from a file or standard input and checks `--expect`, so it is written by hand.
@Action("material write", "텍스트 자료(.tex, 코드, .txt 등) 파일 전체를 바꾸기", done: "자료 '{material}'을(를) 썼습니다",
        phrases: ["tex 수정", "코드 파일 고치기", "텍스트 파일 쓰기"], cli: .manual)
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
        guard !m.isFolder, MaterialFormat(path: m.path).isText else { throw ActionError.rule(String(localized: .errorMaterialNotText(m.path))) }
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
    /// Only UTF-8 is replaced: a file in another encoding would be rewritten as UTF-8, which the program that made it
    /// may not read.
    static func read(_ store: CourseStore, _ path: String) throws -> String {
        do {
            return try store.readText(path)
        } catch StorageError.notUTF8 {
            throw ActionError.rule(String(localized: .errorMaterialNotUtf8(path)))
        }
    }
}

/// Puts the PDF next to the `.tex` under the same name, where tracking already reads it as the source's output. A PDF
/// there that this action didn't write is someone's file: replacing it takes `overwrite`, and it goes to the Trash.
/// No examples: the equivalence test runs each one for real, and CI has no Tectonic.
@Action("material build", "LaTeX 자료(.tex)를 Tectonic으로 PDF로 만들어 옆에 같은 이름으로 둔다", done: "'{material}'을(를) PDF로 만들었습니다",
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
        guard let built = MaterialFormat.builtPDF(of: m.path) else { throw ActionError.rule(String(localized: .errorMaterialNotTex(m.path))) }
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
        let output = try pdf.map { try Self.output($0, of: source) } ?? Self.compile(source)
        try ctx.io(change) { try store.replaceFile(target, with: output, keepOld: exists && !ours) }
        try ctx.edit(course) { f in
            try store.refreshMaterials(in: &f, device: ctx.device, now: ctx.now)
            if let i = f.materials.firstIndex(where: { $0.path == target }) {
                try store.rehash(f.materials[i].id, in: &f, device: ctx.device, now: ctx.now)
                f.materials[i].builtHash = f.materials[i].hash
            }
        }
    }

    /// The file takes a tracked PDF's place and its hash is marked as built, so the next build replaces it without
    /// asking. Any other file passed in could put itself over a course PDF that way.
    static func output(_ path: String, of source: URL) throws -> URL {
        #if os(macOS)
        let folder = TexEngine.outputFolder(for: source).resolvingSymlinksInPath().path + "/"
        let url = URL(filePath: path).resolvingSymlinksInPath()
        guard url.path.hasPrefix(folder) else { throw ActionError.rule(String(localized: .errorBuildOutputElsewhere(path))) }
        return url
        #else
        throw ActionError.rule(String(localized: .errorTexMacOnly))
        #endif
    }

    static func compile(_ source: URL) throws -> URL {
        #if os(macOS)
        guard let engine = TexEngine.locate() else { throw ActionError.rule(String(localized: .errorTexNotInstalled)) }
        let build = try engine.compile(source, into: TexEngine.outputFolder(for: source))
        guard let pdf = build.pdf else {
            throw ActionError.rule(String(localized: .errorTexFailed(build.errors.map(\.description).joined(separator: "\n"))))
        }
        return pdf
        #else
        throw ActionError.rule(String(localized: .errorTexMacOnly))
        #endif
    }
}

/// A note's PDF goes to `Notes/Exports/<title>.pdf` (an exam summary's to Exercises), not beside it: Notes/ holds only
/// notes. The place is chosen by title, so two notes can share it and another tool's export may already be there; as
/// with `material build`, only a PDF this action wrote is replaced without `overwrite`, and a replaced one goes to the
/// Trash. No examples, for the same reason as `material build`.
@Action("note build", "LaTeX 노트(.tex)를 Tectonic으로 PDF로 만들어 Notes/Exports(시험 정리는 Exercises)에 둔다", done: "노트 '{note}'을(를) PDF로 만들었습니다",
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
        let entry = try ctx.file(course).notes.first { $0.id == file.meta.id }
        var ours = false
        if exists, let made = entry?.builtHash { ours = try made == store.hash(target) }
        if exists, !ours, !overwrite {
            throw ActionError.conflict(String(localized: .errorBuildWouldReplace(target)))
        }
        let change = Change(exists ? .changed : .added, try ctx.relative(course, target))
        guard !ctx.dryRun else {
            ctx.record(change)
            return
        }
        let built = try pdf.map { try MaterialBuild.output($0, of: file.url) } ?? MaterialBuild.compile(file.url)
        try ctx.io(change) {
            try FileManager.default.createDirectory(at: store.fileURL(target).deletingLastPathComponent(), withIntermediateDirectories: true)
            try store.replaceFile(target, with: built, keepOld: exists && !ours)
        }
        guard let id = entry?.id else { return }
        let hash = try store.hash(target)
        try ctx.edit(course) { f in
            if let i = f.notes.firstIndex(where: { $0.id == id }) { f.notes[i].builtHash = hash }
        }
    }
}
