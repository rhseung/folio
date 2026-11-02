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
        if let expected, try store.readText(m.path) != expected {
            throw ActionError.conflict(String(localized: .errorMaterialChanged(m.path)))
        }
        try ctx.io(Change(.changed, try ctx.relative(course, m.path))) { try store.writeText(m.path, text: text) }
        guard !ctx.dryRun else { return }
        try ctx.edit(course) { f in try store.rehash(material, in: &f, device: ctx.device, now: ctx.now) }
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
    // A PDF the app already built off the main thread, since a build can take minutes. Without one the action runs
    // Tectonic itself.
    @Hidden var pdf: String?
    /// 같은 이름의 PDF가 Folio가 만든 것이 아니어도 바꾼다
    var overwrite = false

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try ctx.file(course)
        let m = file.materials[try index(material, in: file.materials, .valueMaterial)]
        guard let built = MaterialFormat.builtPDF(of: m.path) else { throw ActionError.rule(String(localized: .errorMaterialNotTex(m.path))) }
        let existing = file.materials.first { $0.id == m.sourceOf }
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
        let output = try pdf.map { URL(filePath: $0) } ?? Self.compile(store.fileURL(m.path))
        try ctx.io(change) { try store.replaceFile(target, with: output, keepOld: exists && !ours) }
        try ctx.edit(course) { f in
            try store.refreshMaterials(in: &f, device: ctx.device, now: ctx.now)
            if let i = f.materials.firstIndex(where: { $0.path == target }) {
                try store.rehash(f.materials[i].id, in: &f, device: ctx.device, now: ctx.now)
                f.materials[i].builtHash = f.materials[i].hash
            }
        }
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
