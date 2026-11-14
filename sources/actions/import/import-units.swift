import FolioDomain
import FolioStorage
import Foundation

@Action(
    "import units", "단원 표를 단원으로",
    discussion: """
        파일마다 {"course": <과목 폴더 이름>, "units": [{"title", "sessions": ["11-03"], "children"}]}. 제목으로 맞춰
        없는 단원만 더하고, 회차 연결은 더하기만 한다.
        """,
    effect: .creates, done: "단원을 가져왔습니다", examples: ["folio import units ~/Downloads/EC4207-units.json --dry-run"], phrases: ["단원 표 가져오기"])
public struct ImportUnits {
    /// 단원 JSON
    @Arg @FromFile("units.json", perItem: true) var files: [UnitFile]

    public func run(_ ctx: ActionContext) throws {
        let ids = try courseIDs(ctx)
        for units in files {
            guard let id = ids[units.course] else {
                ctx.note(String(localized: .noteImportNoFolder(units.course)))
                continue
            }
            let r = UnitImporter.merge(units.units, into: try ctx.file(id), calendar: ctx.calendar, device: ctx.device, now: ctx.now)
            ctx.note(String(localized: .noteImportUnitsCourse(units.course, r.added.count, r.linked.count)))
            for title in r.added { ctx.note("+ \(title)") }
            if !r.unknownSessions.isEmpty {
                ctx.note(String(localized: .noteImportUnitsUnknownSessions(units.course, r.unknownSessions.joined(separator: ", "))))
            }
            if !r.added.isEmpty || !r.linked.isEmpty { try ctx.edit(id) { $0 = r.file } }
        }
    }
}
