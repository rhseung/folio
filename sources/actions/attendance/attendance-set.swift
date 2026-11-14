import FolioDomain
import FolioStorage
import Foundation

@Action(
    "attendance set", "회차의 출결 정하기. 출석이 기본값이다", done: "회차 '{session}'의 출결을 {state}(으)로 정했습니다",
    examples: ["folio attendance set EC4207/10-26 absent"],
    phrases: ["빠졌", "못 갔", "안 갔", "결석", "지각", "공결", "출석 체크", "수업 빠짐", "못 갔어"])
public struct AttendanceSet {
    @Arg var course: Course.ID
    /// 회차
    @Arg var session: Session.ID
    /// 출결
    @Arg var state: AttendanceState

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(session, in: f.sessions, .valueSession)
            f.attendance.removeAll { $0.sessionId == session }
            if state != .present { f.attendance.append(Attendance(device: ctx.device, at: ctx.now, sessionId: session, state: state)) }
        }
    }
}
