import FolioDomain
import FolioStorage
import Foundation

// 명령줄에서 종류가 자료보다 앞에 오므로 먼저 선언한다.
@Action(
    "material kind", "자료의 종류(문제, 제출물, 해설 등) 바꾸기. 여러 개면 확인을 받는다",
    discussion: "과제 폴더의 파일은 종류가 없으면 이름으로 짐작한다(HW3-이름.pdf는 제출물, 나머지는 문제).",
    confirm: "자료 {materials}의 종류를 {kind}(으)로 바꿉니다.", done: "자료 {materials}을(를) {kind}(으)로 바꿨습니다",
    examples: ["folio material kind submission EC4207/26h3.pdf", "folio material kind problem EC4207/26h3.pdf"],
    phrases: ["제출물로 표시", "과제 파일 문제 제출물 구분"])
public struct MaterialKindSet {
    @Arg var course: Course.ID
    /// 종류
    @Arg var kind: MaterialKind
    /// 자료
    @Arg var materials: [Material.ID]

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            for id in materials { _ = try index(id, in: f.materials, .valueMaterial) }
            for i in f.materials.indices where materials.contains(f.materials[i].id) { f.materials[i].kind = kind }
        }
    }
}
