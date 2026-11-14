import FolioDomain
import FolioStorage
import Foundation

@Action(
    "material relink", "사라진 자료를 과목 폴더 안의 다른 파일에 다시 잇기", done: "자료 '{material}'을(를) {file}에 다시 이었습니다",
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
