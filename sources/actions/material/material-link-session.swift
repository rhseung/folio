import FolioDomain
import FolioStorage
import Foundation

@Action(
    "material link", "자료를 회차에 연결하거나 떼기", done: "자료 '{material}'과(와) 회차 '{session}'의 연결을 바꿨습니다",
    phrases: ["자료 수업 연결", "슬라이드 회차에 붙이기"], cli: .manual(reason: "--pages 3-12 한 옵션을 firstPage와 lastPage 두 필드로 나눈다"))
public struct MaterialLinkSession {
    @Arg var course: Course.ID
    @Arg var material: Material.ID
    @Arg var session: Session.ID
    @Off("off") var linked = true
    var firstPage: Int?
    var lastPage: Int?

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            _ = try index(session, in: f.sessions, .valueSession)
            if linked {
                f.linkMaterial(material, session: session, firstPage: firstPage, lastPage: lastPage)
            } else {
                f.unlinkMaterial(material, session: session)
            }
        }
    }
}
