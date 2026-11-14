import FolioDomain
import FolioStorage
import Foundation

@Action(
    "import exams", "캘린더의 시험을 시험으로",
    discussion: """
        exams.json은 구글 캘린더 "시험" 캘린더에서 읽은 CalendarExam 목록이다. 같은 날 시험은 빈 칸만 채우고, 다른 날이면
        바꾸지 않고 알린다.
        """,
    effect: .creates, done: "시험을 가져왔습니다", examples: ["folio import exams ~/Downloads/exams.json --dry-run"],
    phrases: ["캘린더 시험 가져오기", "시험 일정 불러오기"])
public struct ImportExams {
    /// CalendarExam 목록 JSON
    @Arg @FromFile("exams.json") var exams: [CalendarExam]

    public func run(_ ctx: ActionContext) throws {
        let ids = try courseIDs(ctx)
        for (name, group) in Dictionary(grouping: exams, by: \.course).sorted(by: { $0.key < $1.key }) {
            guard let id = ids[name] else {
                ctx.note(String(localized: .noteImportNoFolder(name)))
                continue
            }
            let r = CalendarImporter.mergeExams(group, into: try ctx.file(id), calendar: ctx.calendar, device: ctx.device, now: ctx.now)
            for x in r.added { ctx.note("\(name) + \(x.title) \(shortTime(x.start))–\(shortTime(x.end)) \(x.location)") }
            for x in r.filled {
                ctx.note(
                    "\(name) ~ \(x.title) \(shortTime(x.start))–\(shortTime(x.end)) \(x.location)\(x.memo.isEmpty ? "" : " · \(x.memo)")")
            }
            for c in r.conflicts {
                ctx.note(
                    String(localized: .noteImportExamsConflict(name, c.exam.title, shortTime(c.exam.start), shortTime(c.calendar.start))))
            }
            if r.added.isEmpty && r.filled.isEmpty && r.conflicts.isEmpty { ctx.note(String(localized: .noteImportExamsUnchanged(name))) }
            if !r.added.isEmpty || !r.filled.isEmpty { try ctx.edit(id) { $0 = r.file } }
        }
    }
}
