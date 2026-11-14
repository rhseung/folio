import FolioDomain
import FolioStorage
import Foundation

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
