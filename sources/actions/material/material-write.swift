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
