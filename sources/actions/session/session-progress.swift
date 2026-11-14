import FolioDomain
import FolioStorage
import Foundation

@Action(
    "session progress", "수업의 렉처 진도 기록하기. 자료마다 이번 수업이 다룬 쪽을 회차에 연결한다",
    discussion: "자료마다 <자료>:<시작>-<끝>으로 쓴다. 한 쪽이면 <자료>:<쪽>. 적지 않은 자료의 연결은 그대로 둔다.",
    done: "회차 '{session}'의 진도를 기록했습니다",
    examples: [
        "folio session progress EC4207/10-26 05_Matchings.pdf:3-12", "folio session progress EC4207/10-26 05_Matchings.pdf:18-24 --dry-run",
    ],
    phrases: ["렉처 진도", "수업 진도", "어디까지 나갔", "진도 기록"])
public struct SessionProgress {
    /// 과목
    @Arg var course: Course.ID
    /// 회차
    @Arg var session: Session.ID
    /// 렉처 파일마다 이번 수업이 다룬 쪽
    @Arg @Parsed("material:pages", "05_Matchings.pdf:3-12") var ranges: [SessionMaterial]

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(session, in: f.sessions, .valueSession)
            for range in ranges {
                _ = try index(range.materialId, in: f.materials, .valueMaterial)
                f.linkMaterial(range.materialId, session: session, firstPage: range.firstPage, lastPage: range.lastPage)
            }
        }
    }
}
