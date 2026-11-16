import ArgumentParser
import FolioDomain
import Foundation

struct SkillCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skill", abstract: "에이전트 스킬(SKILL.md) 보기와 설치",
        discussion: """
            Claude Code, Codex 같은 에이전트가 folio를 쓰는 법을 담은 SKILL.md다. 대부분의 에이전트가 같은 형식을 읽는다.

            예시:
              folio skill                              SKILL.md 내용 보기
              folio skill --install ~/.claude/skills   Claude Code에 설치
              folio skill --install ~/.agents/skills --dry-run
            """)
    @OptionGroup var g: GlobalOptions
    @Option(help: ArgumentHelp("이 스킬 폴더 아래 folio/SKILL.md로 설치", valueName: "dir"), completion: .directory) var install: String?

    func run() throws {
        guard let install else { return say(Skill.text) }
        let url = URL(filePath: (install as NSString).expandingTildeInPath, directoryHint: .isDirectory).appending(path: "folio/SKILL.md")
        let old = try? String(contentsOf: url, encoding: .utf8)
        if old == Skill.file {
            return g.json ? try printJSON(["path": url.path, "status": "unchanged"]) : say("✓".styled(.green) + " 이미 최신입니다: \(url.path)")
        }
        if old != nil, !g.dryRun { try ask("\(url.path)를 새 내용으로 바꿉니다.", g) }
        if !g.dryRun {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(Skill.file.utf8).write(to: url, options: .atomic)
        }
        let status = g.dryRun ? "dry-run" : old == nil ? "installed" : "updated"
        if g.json { return try printJSON(["path": url.path, "status": status]) }
        say((g.dryRun ? "미리보기".styled(.bold) + " · " : "✓".styled(.green) + " ") + (old == nil ? "설치" : "갱신") + ": \(url.path)")
    }
}
