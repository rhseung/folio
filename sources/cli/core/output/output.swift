import FolioStorage
import Foundation

func say(_ line: String = "") { Sink.current.out(line) }
func warn(_ line: String) { Sink.current.err(line) }

func printJSON(_ value: some Encodable) throws {
    say(String(decoding: try JSONEncoder.folio.encode(value), as: UTF8.self))
}

extension String {
    func styled(_ styles: Style...) -> String {
        guard Style.enabled, !styles.isEmpty, !isEmpty else { return self }
        return "\u{1B}[\(styles.map(\.sgr).joined(separator: ";"))m\(self)\u{1B}[0m"
    }

    func course(_ token: String) -> String {
        let ansi: [String: Style] = [
            "violet": .magenta, "pink": .magenta, "blue": .blue, "teal": .cyan, "green": .green,
            "orange": .yellow, "olive": .yellow, "red": .red,
        ]
        return ansi[token].map { styled($0) } ?? styled(.dim)
    }

    var toned: String {
        switch self {
        case "present", "submitted", "graded", "good", "easy": styled(.green)
        case "late", "todo", "doing", "hard", "unclassified": styled(.yellow)
        case "absent", "again", "missing": styled(.red)
        case "excused", "quiz", "midterm", "final": styled(.cyan)
        case "ignored", "pass_fail", "휴강": styled(.dim)
        default: self
        }
    }

    func highlighting(_ words: [String]) -> String {
        guard Style.enabled else { return self }
        var marked: [Range<String.Index>] = []
        for w in words where !w.isEmpty {
            var from = startIndex
            while let r = range(of: w, options: [.caseInsensitive], range: from..<endIndex) {
                marked.append(r)
                from = r.upperBound
            }
        }
        var out = "", at = startIndex
        for r in marked.sorted(by: { $0.lowerBound < $1.lowerBound }) where r.lowerBound >= at {
            out += self[at..<r.lowerBound] + String(self[r]).styled(.yellow, .bold)
            at = r.upperBound
        }
        return out + self[at...]
    }

    func link(_ url: URL) -> String {
        guard Style.enabled else { return self }
        return "\u{1B}]8;;\(url.absoluteString)\u{1B}\\\(self)\u{1B}]8;;\u{1B}\\"
    }
}

// MARK: Width

extension Character {
    // Foundation과 Noora 모두 한글을 넓은 글자로 세지 않는다(Noora는 `isIdeographic`만 본다). 표가 한국어 이름과 줄을
    // 맞춰야 하므로 East Asian Wide와 Fullwidth 범위를 여기 둔다.
    var columns: Int {
        guard let s = unicodeScalars.first else { return 0 }
        if s.properties.generalCategory == .nonspacingMark || s.properties.generalCategory == .format { return 0 }
        if s.properties.isEmojiPresentation { return 2 }
        switch s.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
            0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }
}

extension String {
    var columns: Int { plain.reduce(0) { $0 + $1.columns } }

    var plain: String { replacing(Self.escape, with: "") }

    nonisolated(unsafe) static let escape = #/\x{1B}\[[0-9;]*m|\x{1B}\]8;;[^\x{1B}]*\x{1B}\\/#

    func padded(to width: Int) -> String { self + String(repeating: " ", count: max(0, width - columns)) }

    func truncated(to width: Int) -> String {
        guard columns > width else { return self }
        var out = "", used = 0, at = startIndex, styled = false
        while at < endIndex {
            if let m = self[at...].prefixMatch(of: Self.escape) {
                out += m.output
                styled = true
                at = m.range.upperBound
                continue
            }
            let c = self[at]
            if used + c.columns > width - 1 { break }
            out.append(c)
            used += c.columns
            at = index(after: at)
        }
        // 잘린 뒤의 코드도 실행해야 그 앞에서 연 링크나 색이 닫힌다.
        return out + self[at...].matches(of: Self.escape).map { String($0.output) }.joined() + (styled ? "\u{1B}[0m" : "") + "…"
    }
}

var terminalWidth: Int? {
    guard Style.isTerminal else { return nil }
    var size = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 { return Int(size.ws_col) }
    return Int(ProcessInfo.processInfo.environment["COLUMNS"] ?? "")
}
