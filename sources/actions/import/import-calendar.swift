import FolioDomain
import FolioStorage
import Foundation

@Action(
    "import calendar", "캘린더의 수업을 회차로",
    discussion: """
        meetings.json은 CalendarMeeting 목록이다. 이미 있는 회차는 빈 시각만 채우고, 범위 안에서 수업이 없는 날의
        회차는 휴강으로 표시하며, 수업 제목과 같은 이름의 복습 노트를 연결한다. lab 번호가 있는 수업은 그 실험의 단원(없으면
        Lab<번호> <수업 제목>으로 만든다)에 연결한다.
        """,
    effect: .creates, done: "캘린더 수업을 가져왔습니다", examples: ["folio import calendar ~/Downloads/meetings.json --dry-run"],
    phrases: ["캘린더 수업 가져오기", "시간표 가져오기"])
public struct ImportCalendar {
    /// CalendarMeeting 목록 JSON
    @Arg @FromFile("meetings.json") var meetings: [CalendarMeeting]

    public func run(_ ctx: ActionContext) throws {
        let ids = try courseIDs(ctx)
        let semesters = try ctx.transcript().semesters
        for (name, group) in Dictionary(grouping: meetings, by: \.course).sorted(by: { $0.key < $1.key }) {
            guard let id = ids[name] else {
                ctx.note(String(localized: .noteImportCalendarNoFolder(name, group.count)))
                continue
            }
            let store = try ctx.store(id)
            let file = try ctx.file(id)
            guard let start = semesters.first(where: { $0.id == file.course.semesterId })?.start else {
                ctx.note(String(localized: .noteImportCalendarNoStart(name)))
                continue
            }

            let r = CalendarImporter.merge(
                group, into: file, semesterStart: start, calendar: ctx.calendar, device: ctx.device, now: ctx.now)
            let notes = store.notes(in: file)
            let links = CalendarImporter.noteLinks(
                sessions: r.file.sessions, titles: r.titles, notes: notes.compactMap { n in n.meta.id.map { ($0, n.title, n.meta) } })
            ctx.note(String(localized: .noteImportCalendarCourse(name, r.added.count, r.filled.count, r.cancelled.count, links.count)))
            if !r.schedule.isEmpty {
                ctx.note(
                    String(
                        localized: .noteImportCalendarSchedule(
                            name,
                            r.schedule.map {
                                "\(ClassTime.weekdayNames[$0.weekday - 1]) \(String(format: "%02d:%02d-%02d:%02d", $0.startMinute / 60, $0.startMinute % 60, $0.endMinute / 60, $0.endMinute % 60)) \($0.room)"
                            }.joined(separator: ", "))))
            }

            let label = { (s: Session) in r.file.units(of: s).first?.title ?? r.titles[s.id] ?? "" }
            for s in r.added {
                ctx.note(
                    "+ \(r.file.reference(of: s, calendar: ctx.calendar)) \(weekdayTime(s.date))\(label(s).isEmpty ? "" : " · \(label(s))")"
                )
            }
            for s in r.filled {
                ctx.note(
                    "~ \(r.file.reference(of: s, calendar: ctx.calendar)) \(weekdayTime(s.date))\(label(s).isEmpty ? "" : " · \(label(s))")"
                )
            }
            for s in r.cancelled {
                ctx.note(
                    String(localized: .noteImportCalendarCancelled(r.file.reference(of: s, calendar: ctx.calendar), weekdayTime(s.date))))
            }

            var result = r.file
            for l in links {
                guard let note = notes.first(where: { $0.meta.id == l.note }), let n = result.notes.firstIndex(where: { $0.id == l.note }),
                    let i = result.sessions.firstIndex(where: { $0.id == l.session })
                else { continue }
                ctx.note(
                    String(
                        localized: .noteImportCalendarNoteLink(result.reference(of: result.sessions[i], calendar: ctx.calendar), note.title)
                    ))
                result.notes[n].kind = .review
                result.notes[n].touch(by: ctx.device, at: ctx.now)
                result.sessions[i].reviewNoteId = l.note
                result.sessions[i].touch(by: ctx.device, at: ctx.now)
            }
            try ctx.edit(id) { $0 = result }
        }
    }
}
