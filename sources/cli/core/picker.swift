import FolioActions
import FolioDomain
import FolioStorage
import Foundation

// 에이전트가 기다리는 프롬프트가 아니라 종료 코드 3을 받도록, fzf는 사람이 터미널에 있을 때만 쓴다.
enum Picker {
    nonisolated(unsafe) static var allowed = false
    nonisolated(unsafe) static var gist: String?

    static func enable(_ options: GlobalOptions) {
        // 테스트는 overrides로 명령을 나란히 돌리는데, 각각 이 static을 보호 없이 쓰면 테스트 프로세스가 멈췄다.
        guard CLI.overrides == nil else { return }
        let env = ProcessInfo.processInfo.environment
        allowed = !options.json && !options.noPick && env["FOLIO_NO_PICK"] == nil && isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
        gist = try? CLI.gist(options).url.path
    }

    static func choose(_ lines: [String], prompt: String) -> String? {
        run(lines, prompt: prompt, multi: false).first
    }

    static func chooseMany(_ lines: [String], prompt: String) -> [String] {
        run(lines, prompt: prompt, multi: true)
    }

    static let previews = [
        "과목": "course", "학기": "semester", "회차": "session", "시험": "exam", "단원": "unit", "과제": "assignment", "노트": "note", "자료": "material",
    ]

    static func run(_ lines: [String], prompt: String, multi: Bool) -> [String] {
        guard allowed else { return [] }
        let quoted = { (s: String) in "'" + s.replacing("'", with: "'\\''") + "'" }
        let folder = gist.map { " --gist " + quoted($0) } ?? ""
        let preview = previews[prompt].map { ["--preview=\(quoted(CommandLine.arguments[0])) \($0) show {}\(folder)"] } ?? []
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/env")
        let extra = (ProcessInfo.processInfo.environment["FOLIO_FZF_OPTS"] ?? "").split(separator: " ").map(String.init)
        p.arguments = ["fzf", "--height=40%", "--reverse", "--prompt=\(prompt)> "] + (multi ? ["--multi"] : []) + preview + extra
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        guard (try? p.run()) != nil else { return [] }
        input.fileHandleForWriting.write(Data(lines.joined(separator: "\n").utf8))
        try? input.fileHandleForWriting.close()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return [] }
        let picked = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(
            String.init)
        return picked.filter(lines.contains)
    }
}
