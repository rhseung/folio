import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct CleanupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup", abstract: "예전 폴더를 표준 구조로 정리: 계획, 적용, 되돌리기",
        subcommands: [Plan.self, Apply.self, Undo.self])

    static let reasonText: [ReviewReason: String] = [
        .guessedWeek: "주차 추정",
        .unknownWeek: "주차 모름",
        .guessedNumber: "과제 번호 추정",
        .unknownNumber: "과제 번호 모름",
        .guessedExam: "대상 시험 추정",
        .pastExamNameKept: "족보 이름 유지",
        .guessedFolder: "위치 추정",
        .unknownFile: "분류 불명",
        .unknownFolder: "대응 폴더 없음",
        .nameCollision: "이름 충돌",
    ]

    struct Plan: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "옮길 계획을 만들어 보여 주기. 아무것도 옮기지 않는다", discussion: """
            예시:
              folio cleanup plan --out plan.json
              folio cleanup plan --out plan.json --skip 2026-2/과대표
            """)
        @OptionGroup var g: GlobalOptions
        @Option(help: ArgumentHelp("계획을 저장할 파일. cleanup apply가 읽는다", valueName: "file"), completion: .file()) var out: String?
        @Option(help: ArgumentHelp("건드리지 않을 GIST 기준 경로. 여러 번 줄 수 있다", valueName: "path"), completion: .file(extensions: ["json"])) var skip: [String] = []

        func run() throws {
            let gist = try CLI.gist(g)
            let plan = CleanupPlanner.plan(try gist.readTree(), skip: Set(skip))
            if let out { try StoredDocument(new: plan).write(to: URL(filePath: absolute(out))) }
            if g.json { return try printJSON(plan) }
            say("정리 계획".styled(.bold) + "  " + "이동 \(plan.moves.count)건 · 검토 필요 \(plan.moves.filter { $0.review != nil }.count)건".styled(.dim))
            // Grouped by destination: `<semester>/<course>` or `<semester>/_Admin`.
            let groups = Dictionary(grouping: plan.moves) { $0.to.split(separator: "/").prefix(2).joined(separator: "/") }
            for group in groups.keys.sorted() {
                let semester = group.split(separator: "/")[0]
                let rel = { (path: String) in
                    String(path.hasPrefix(group + "/") ? path.dropFirst(group.count + 1) : path.dropFirst(semester.count + 1))
                }
                say()
                say(group.styled(.bold))
                var t = Table(header: ["원래 위치", "옮길 위치", "검토"], shrink: [0, 1])
                for m in groups[group]!.sorted(by: { $0.from < $1.from }) {
                    t.rows.append([rel(m.from), rel(m.to), m.review.map { CleanupCommand.reasonText[$0]!.styled(.yellow) } ?? ""])
                }
                t.print()
            }
            if !plan.skipped.isEmpty {
                say()
                say("건너뜀".styled(.bold))
                for s in plan.skipped { say("  \(s)") }
            }
        }
    }

    struct Apply: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "검토한 계획대로 옮기기. 먼저 GIST 폴더 전체를 백업한다", discussion: """
            검토가 필요한 이동은 --include-flagged가 있어야 옮긴다. moves.jsonl에 한 묶음으로 남아 cleanup undo로 되돌릴 수 있다.
            확인을 받는다.

            예시:
              folio cleanup apply --plan plan.json --backup ~/Backups/Folio --dry-run
              folio cleanup apply --plan plan.json --backup ~/Backups/Folio --include-flagged
            """)
        @OptionGroup var g: GlobalOptions
        @Option(help: ArgumentHelp("cleanup plan이 만든 파일", valueName: "file"), completion: .file()) var plan: String
        @Option(help: ArgumentHelp("백업을 둘 iCloud 밖 폴더", valueName: "folder"), completion: .directory) var backup: String
        @Flag(help: "검토가 필요한 이동까지") var includeFlagged = false

        func run() throws {
            let ctx = try CLI.context(g)
            let file = try StoredDocument<CleanupPlan>.read(from: URL(filePath: absolute(plan))).model
            let moves = includeFlagged ? file.moves : file.moves.filter { $0.review == nil }
            if !g.dryRun {
                // Asked before the backup, so a declined run leaves no copy behind.
                try ask("파일과 폴더 \(moves.count)개를 옮깁니다.", g)
                let copy = try ctx.gist.backup(into: URL(filePath: absolute(backup)), now: ctx.now)
                if !g.json { say("백업: \(copy.path)".styled(.dim)) }
            }
            var options = g
            options.yes = true
            let result = try perform(spec: CleanupApply(moves: moves), options, ctx: ctx)
            if !g.json, let batch = result.made { say("  되돌리기: folio cleanup undo \(batch.uuidString)".styled(.dim)) }
        }
    }

    struct Undo: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "cleanup apply나 material mv로 옮긴 묶음을 되돌리기", discussion: """
            확인을 받는다.

            예시:
              folio cleanup undo 6A1F0C2E-3B4D-4E5F-8A9B-0C1D2E3F4A5B --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("묶음 ID", valueName: "batch"), completion: Complete.problemSets) var batch: UUID

        func run() throws {
            try perform(spec: CleanupUndo(batch: batch), g, ctx: try CLI.context(g))
        }
    }
}
