import FolioDomain
import FolioStorage
import Foundation

// 사용자가 정한 범위를 지키고, 앞 파일로 돌아간 수업이 그 범위를 이 수업에서 본 쪽으로 줄이지 않도록, 회차에 연결이
// 없는 파일만 연결한다.
@Action(
    "session link-viewed", "녹음 중 본 강의 페이지를 회차에 연결하기. 연결이 없는 자료만 더하고 있는 연결은 그대로 둔다",
    discussion: "앱 안의 PDF 보기에서 20초 이상 머문 페이지의 처음부터 끝까지가 범위다. 녹음이 끝나면 앱이 부른다.",
    done: "회차 '{session}'에 녹음 중 본 페이지를 연결했습니다",
    examples: ["folio session link-viewed EC4207/10-26 --dry-run"], phrases: ["녹음 중 본 페이지", "본 페이지 연결", "수업 중 본 슬라이드"])
public struct SessionLinkViewed {
    @Arg var course: Course.ID
    /// 회차
    @Arg var session: Session.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(session, in: f.sessions, .valueSession)
            for recording in f.recordings where recording.sessionId == session { f.linkViewedPages(of: recording) }
        }
    }
}
