import FolioDomain
import FolioStorage
import Foundation

@Action(
    "session add", "회차 추가. 주차는 학기 시작일에서 정한다", effect: .creates, done: "회차를 추가했습니다",
    examples: [
        #"folio session add EC4207 --date "2026-10-28 10:30""#, "folio session add EC4207 --date 2026-10-30 --kind cancelled --dry-run",
        #"folio session add EC4207 --date "2026-11-04 21:00" --end "2026-11-04 22:15" --kind makeup --link https://zoom.us/j/123 --dry-run"#,
        #"folio session add EC4207 --date "2026-11-11 10:30" --attendance absent --dry-run"#,
    ],
    phrases: ["보충", "보충수업", "잡혔", "수업 추가", "보강", "추가 수업", "회차 만들기", "줌 수업", "온라인 수업", "비대면 수업"])
public struct SessionAdd {
    @New var id: Session.ID
    /// 과목
    @Arg var course: Course.ID
    /// 일시. 2026-10-28 또는 "2026-10-28 10:30"
    var date: Date
    /// 끝 일시. 수업 시간표에 없는 시간일 때만 필요하다
    var end: Date?
    /// 온라인 수업 링크(Zoom 등)
    var link: String?
    /// 종류. lecture(강의), cancelled(휴강), makeup(보강)
    var kind: Session.Kind = .lecture
    /// 출결. 결석이나 공결을 미리 알 때. 휴강과 함께 줄 수 없다
    var attendance: AttendanceState?
    /// 이 수업이 다룰 단원
    @CLIName("unit") var units: [FolioDomain.Unit.ID] = []

    public func run(_ ctx: ActionContext) throws {
        let start = try ctx.semester(of: ctx.file(course).course)?.start
        try ctx.edit(course) { f in
            guard !f.sessions.contains(where: { $0.id == id }) else {
                throw ActionError.rule(String(localized: .errorIdTakenSession("\(id)")))
            }
            for unit in units { _ = try index(unit, in: f.units, .valueUnit) }
            var s = SessionPlanner.session(
                at: date, sessions: f.sessions, termStart: start, calendar: ctx.calendar,
                device: ctx.device, now: ctx.now)
            s.id = id
            s.kind = kind
            s.link = OnlineLink.stored(link)
            s.setEnd(end, schedule: f.course.schedule, calendar: ctx.calendar)
            f.sessions.append(s)
            for unit in Set(units) { f.toggle(session: id, unit: unit) }
            if let attendance, attendance != .present {
                f.attendance.append(Attendance(device: ctx.device, at: ctx.now, sessionId: id, state: attendance))
            }
        }
        ctx.made(id)
    }
}
