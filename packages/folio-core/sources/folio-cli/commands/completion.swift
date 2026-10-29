import ArgumentParser
import FolioActions
import FolioStorage
import Foundation

struct CompletionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completion", abstract: "셸 완성 스크립트",
        discussion: """
            과목과 항목 이름도 실제 데이터에서 완성한다. 후보에는 과목 이름을 설명으로 붙인다.

            예시:
              folio completion zsh > ~/.zfunc/_folio
              source <(folio completion bash)
            """)

    @Argument(help: "zsh, bash, fish") var shell: String

    func run() throws {
        guard let s = CompletionShell(rawValue: shell) else { throw CLIError(exit: .usage, message: "셸은 zsh, bash, fish 중 하나입니다") }
        say(Folio.completionScript(for: s))
    }
}

enum Complete {
    /// A `GlobalOptions()` made by hand has no parsed values and traps when read, so `--gist` is taken from the words.
    static func resolver(_ words: [String] = []) -> Resolver? {
        let given = words.firstIndex(of: "--gist").flatMap { words.indices.contains($0 + 1) ? words[$0 + 1] : nil }
        return (try? CLI.gist(path: given)).map { Resolver(ActionContext(gist: $0, device: UUID())) }
    }

    /// zsh and fish show a note beside each candidate (fzf-tab too), so a list of codes says what each one is. bash has
    /// nowhere to put one. zsh splits value and note at the first unescaped colon.
    static func described(_ pairs: [(String, String)]) -> [String] {
        pairs.map { value, note in
            switch CompletionShell.requesting {
            case .zsh: value.replacing(":", with: "\\:") + (note.isEmpty ? "" : ":" + note)
            case .fish: note.isEmpty ? value : value + "\t" + note
            default: value
            }
        }
    }

    static func courses(_ words: [String], _ index: Int, _ prefix: String) -> [String] {
        guard let r = resolver(words) else { return [] }
        return described(r.courses.map { ($0.code, title(r, $0)) })
    }

    /// `그래프 이론 · 2026-3`.
    static func title(_ r: Resolver, _ c: CourseRef) -> String {
        let semester = r.semesters.first { $0.id == c.course.semesterId }?.folder?.name
        return ([c.course.title] + (semester.map { [$0] } ?? [])).joined(separator: " · ")
    }

    static func day(_ date: Date?, _ r: Resolver) -> String { date.map { when($0, now: r.ctx.now).plain } ?? "" }

    static func joined(_ parts: String...) -> String { parts.filter { !$0.isEmpty }.joined(separator: " · ") }

    static func items(_ kind: @escaping @Sendable (Resolver, CourseRef) -> [(String, String)]) -> CompletionKind {
        .custom { words, _, prefix in
            guard let r = resolver(words) else { return [] }
            if let slash = prefix.firstIndex(of: "/"), let c = try? r.course(String(prefix[..<slash])) {
                return described(kind(r, c).map { ("\(c.code)/\($0.0)", $0.1) })
            }
            return described(r.courses.map { ("\($0.code)/", title(r, $0)) })
        }
    }

    static let sessions = items { r, c in
        c.file.map { f in f.sessions.map { s in (f.name(of: s), joined(day(s.date, r), s.isCancelled ? "휴강" : s.topic)) } } ?? []
    }
    static let exams = items { r, c in c.file?.exams.map { ($0.title, joined($0.kind.rawValue, day($0.start, r))) } ?? [] }
    static let units = items { _, c in c.file?.units.map { ($0.title, "") } ?? [] }
    static let assignments = items { r, c in c.file?.assignments.map { ($0.title, joined($0.status.rawValue, day($0.due, r))) } ?? [] }
    static let materials = items { _, c in c.file?.materials.map { ($0.path, $0.role?.rawValue ?? "") } ?? [] }
    static let components = items { _, c in c.file?.components.map { ($0.name, "\($0.weight.formatted())%") } ?? [] }
    static let problemSets = items { _, c in c.file?.problemSets.map { ($0.title, "") } ?? [] }
    static let notes = items { _, c in
        guard let store = c.store else { return [] }
        return ((try? store.notes()) ?? []).map { n in
            let path = store.coursePath(of: n.url) ?? n.title
            return (path, path.hasSuffix(n.title + ".md") ? "" : n.title)
        }
    }

    static func semesters(_ words: [String], _ index: Int, _ prefix: String) -> [String] {
        guard let r = resolver(words) else { return [] }
        return described(r.semesters.compactMap { s in
            s.folder.map { ($0.name, "과목 \(r.courses.filter { $0.course.semesterId == s.id }.count)개") }
        })
    }

    /// `--component 과제` names an item of the course given earlier on the line, so that course's items are offered.
    static let componentNames = CompletionKind.custom { words, _, _ in
        guard let r = resolver(words) else { return [] }
        let course = words.dropFirst().lazy.filter { !$0.hasPrefix("-") }.compactMap { try? r.course($0) }.first
        return described(course?.file?.components.map { ($0.name, "\($0.weight.formatted())%") } ?? [])
    }
}
