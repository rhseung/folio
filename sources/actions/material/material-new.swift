import FolioDomain
import FolioStorage
import Foundation

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
