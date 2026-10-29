import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct BackupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backup", abstract: "날짜별 백업: 만들기, 목록, 과목 단위로 꺼내기", subcommands: [Create.self, List.self, Restore.self])

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "오늘 백업을 만든다", discussion: """
            GIST의 .folio와 각 과목의 Notes, Ink, .folio를 설정의 백업 폴더(기본 ~/Backups/Folio/auto)에 Folio-<날짜>.zip으로 묶는다.
            오늘 백업이 있으면 바꾼다. 보관 기간이 지난 백업은 지운다. GIST 폴더는 바뀌지 않는다.

            예시:
              folio backup create --dry-run
              folio backup create
            """)
        @OptionGroup var g: GlobalOptions

        func run() throws {
            try perform(spec: BackupCreate(), g, ctx: try CLI.context(g))
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "백업 목록, 새것부터", discussion: """
            예시:
              folio backup list
              folio backup list --json
            """)
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let ctx = try CLI.context(g)
            let folder = URL(filePath: (try ctx.settings().backup.folder as NSString).expandingTildeInPath, directoryHint: .isDirectory)
            let archives = BackupStore(gist: ctx.gist, folder: folder).archives()
            struct Row: Encodable { var day: String; var path: String }
            if g.json { return try printJSON(archives.map { Row(day: $0.day.description, path: $0.url.path(percentEncoded: false)) }) }
            var t = Table(header: ["날짜", "파일"], shrink: [1])
            for a in archives { t.rows.append([a.day.description, a.url.path(percentEncoded: false).link(a.url)]) }
            t.print()
            footer(archives.count)
        }
    }

    struct Restore: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "한 과목을 백업에서 새 폴더로 꺼낸다", discussion: """
            과목의 Notes, Ink, .folio를 백업 폴더 옆 restored 폴더에 새로 꺼낸다. GIST 폴더는 건드리지 않으니 비교해서 직접 옮긴다.

            예시:
              folio backup restore EC4207 2026-10-27 --dry-run
              folio backup restore EC4207 2026-10-27
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String
        @Argument(help: ArgumentHelp("백업 날짜. 2026-10-27", valueName: "day")) var day: LocalDate

        func run() throws {
            let ctx = try CLI.context(g)
            let c = try Resolver(ctx).course(course)
            try perform(spec: BackupRestore(course: c.id, day: day), g, ctx: ctx)
        }
    }
}
