import FolioDomain
import FolioStorage
import Foundation

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
