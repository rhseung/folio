import ArgumentParser
import FolioActions
import FolioStorage
import Foundation

struct CompletionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completion", abstract: String(localized: .completionAbstract),
        discussion: String(localized: .completionDiscussion))

    @Argument(help: "zsh, bash, fish") var shell: String

    func run() throws {
        guard let s = CompletionShell(rawValue: shell) else {
            throw CLIError(exit: .usage, message: String(localized: .completionUnknownShell))
        }
        say(Folio.completionScript(for: s))
    }
}

enum Complete {
    // 손으로 만든 `GlobalOptions()`에는 파싱한 값이 없어 읽으면 멈추므로, `--gist`를 낱말에서 읽는다.
    static func resolver(_ words: [String] = []) -> Resolver? {
        let given = words.firstIndex(of: "--gist").flatMap { words.indices.contains($0 + 1) ? words[$0 + 1] : nil }
        return (try? CLI.gist(path: given)).map { Resolver(ActionContext(gist: $0, device: UUID())) }
    }

    // zsh와 fish(fzf-tab도)는 후보 옆에 설명을 보이므로 코드 목록이 각 코드가 무엇인지 말할 수 있다. bash에는 설명을 둘
    // 곳이 없다. zsh는 이스케이프하지 않은 첫 콜론에서 값과 설명을 나눈다.
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
        c.file.sessions.map { s in
            (
                c.file.reference(of: s, calendar: r.ctx.calendar),
                joined(
                    day(s.date, r),
                    s.isCancelled
                        ? String(localized: .completionCancelled)
                        : joined(s.kind == .makeup ? String(localized: .completionMakeup) : "", c.file.subject(of: s) ?? ""))
            )
        }
    }
    static let exams = items { r, c in c.file.exams.map { ($0.title, day($0.start, r)) } }
    static let units = items { _, c in c.file.units.map { ($0.title, "") } }
    static let assignments = items { r, c in c.file.assignments.map { ($0.title, joined($0.status.rawValue, day($0.due, r))) } }
    static let materials = items { _, c in c.file.materials.map { ($0.path, $0.role?.rawValue ?? "") } }
    static let components = items { _, c in c.file.components.map { ($0.name, "\($0.weight.formatted())%") } }
    static let problemSets = items { _, c in c.file.problemSets.map { ($0.title, "") } }
    static let notes = items { _, c in
        let store = c.store
        return ((try? store.notes()) ?? []).map { n in
            let path = store.coursePath(of: n.url) ?? n.title
            return (path, path.hasSuffix(n.title + ".md") ? "" : n.title)
        }
    }

    static func semesters(_ words: [String], _ index: Int, _ prefix: String) -> [String] {
        guard let r = resolver(words) else { return [] }
        return described(
            r.semesters.compactMap { s in
                s.folder.map {
                    ($0.name, String(localized: .completionSemesterCourses(r.courses.filter { $0.course.semesterId == s.id }.count)))
                }
            })
    }

    static let componentNames = CompletionKind.custom { words, _, _ in
        guard let r = resolver(words) else { return [] }
        let course = words.dropFirst().lazy.filter { !$0.hasPrefix("-") }.compactMap { try? r.course($0) }.first
        return described(course?.file.components.map { ($0.name, "\($0.weight.formatted())%") } ?? [])
    }
}
