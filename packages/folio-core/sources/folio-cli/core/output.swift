import FolioStorage
import Foundation

/// docs/SPEC.md "출력": every failure maps to one of these.
enum Exit: Int32 {
    case success = 0, unexpected = 1, usage = 2, notFound = 3, rule = 4, needsConfirmation = 5, conflict = 6, coverage = 7

    var code: String {
        switch self {
        case .success: "success"
        case .unexpected: "unexpected"
        case .usage: "usage"
        case .notFound: "not_found"
        case .rule: "rule"
        case .needsConfirmation: "needs_confirmation"
        case .conflict: "conflict"
        case .coverage: "coverage"
        }
    }
}

/// A failure the CLI reports itself, with what to run instead.
struct CLIError: Error {
    var exit: Exit
    var message: String
    /// Refs the user can pass instead, e.g. the courses an ambiguous name matched.
    var candidates: [String] = []
    /// Runnable commands that fix it, shown under the message.
    var hints: [String] = []
}

/// Where output goes. Tests swap it out to keep the test log clean and to read what a command printed.
final class Sink: @unchecked Sendable {
    var out: (String) -> Void
    var err: (String) -> Void
    init(out: @escaping (String) -> Void, err: @escaping (String) -> Void) {
        self.out = out
        self.err = err
    }

    @TaskLocal static var current = Sink(out: { print($0) }, err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
}

func say(_ line: String = "") { Sink.current.out(line) }
func warn(_ line: String) { Sink.current.err(line) }

/// Same field names and date format as course.json (docs/SPEC.md "출력").
func printJSON(_ value: some Encodable) throws {
    say(String(decoding: try JSONEncoder.folio.encode(value), as: UTF8.self))
}

// MARK: Style

/// The terminal's 16 colors, so light and dark themes both read (docs/SPEC.md "사람용 출력").
enum Style {
    case bold, dim, green, yellow, red, blue, magenta, cyan

    static let isTerminal = isatty(STDOUT_FILENO) == 1
    static let enabled = isTerminal && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
    static let trueColor = ["truecolor", "24bit"].contains(ProcessInfo.processInfo.environment["COLORTERM"] ?? "")

    var sgr: String {
        switch self {
        case .bold: "1"
        case .dim: "2"
        case .green: "32"
        case .yellow: "33"
        case .red: "31"
        case .blue: "34"
        case .magenta: "35"
        case .cyan: "36"
        }
    }
}

extension String {
    func styled(_ styles: Style...) -> String {
        guard Style.enabled, !styles.isEmpty, !isEmpty else { return self }
        return "\u{1B}[\(styles.map(\.sgr).joined(separator: ";"))m\(self)\u{1B}[0m"
    }

    /// A course's accent from `#RRGGBB`; the nearest of the 256 colors where the terminal lacks true color.
    func accent(_ hex: String) -> String {
        guard Style.enabled, hex.count == 7, hex.hasPrefix("#"), let v = Int(hex.dropFirst(), radix: 16) else { return self }
        let (r, g, b) = (v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF)
        if Style.trueColor { return "\u{1B}[38;2;\(r);\(g);\(b)m\(self)\u{1B}[0m" }
        let step = { (c: Int) in c < 48 ? 0 : c < 115 ? 1 : (c - 35) / 40 }
        return "\u{1B}[38;5;\(16 + 36 * step(r) + 6 * step(g) + step(b))m\(self)\u{1B}[0m"
    }

    /// A course's color token (`CourseColor.token`): a picked `#RRGGBB` as is, a preset as the nearest of the
    /// terminal's own 16 colors, which the user's theme already tunes for its background.
    func course(_ token: String) -> String {
        if token.hasPrefix("#") { return accent(token) }
        let ansi: [String: Style] = ["violet": .magenta, "pink": .magenta, "blue": .blue, "teal": .cyan, "green": .green,
                                     "orange": .yellow, "olive": .yellow, "red": .red]
        return ansi[token].map { styled($0) } ?? styled(.dim)
    }

    /// Enum values read by what they mean for the user: done green, at risk yellow, missed red, set aside dim.
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

    /// The words of a search marked where they occur, ignoring case. Ranges come from the plain text, so one word can't
    /// match inside the escape codes another word's mark added.
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

    /// A clickable path where the terminal supports OSC 8.
    func link(_ url: URL) -> String {
        guard Style.enabled else { return self }
        return "\u{1B}]8;;\(url.absoluteString)\u{1B}\\\(self)\u{1B}]8;;\u{1B}\\"
    }
}

// MARK: Width

extension Character {
    /// Terminal columns. Neither Foundation nor Noora counts Hangul as wide (Noora only checks `isIdeographic`), and
    /// tables must line up with Korean names, so East Asian Wide and Fullwidth ranges are listed here.
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
    /// Columns once escape sequences are left out.
    var columns: Int { plain.reduce(0) { $0 + $1.columns } }

    var plain: String { replacing(Self.escape, with: "") }

    nonisolated(unsafe) static let escape = #/\x{1B}\[[0-9;]*m|\x{1B}\]8;;[^\x{1B}]*\x{1B}\\/#

    func padded(to width: Int) -> String { self + String(repeating: " ", count: max(0, width - columns)) }

    /// Cut to `width` columns with `…`. Escape codes are copied through without counting, so a search match or a colored
    /// code stays marked up to the cut.
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
        // The codes past the cut still run, so a link or color opened before it gets closed.
        return out + self[at...].matches(of: Self.escape).map { String($0.output) }.joined() + (styled ? "\u{1B}[0m" : "") + "…"
    }
}

/// Terminal width, or nil when output is not a terminal (then nothing is cut).
var terminalWidth: Int? {
    guard Style.isTerminal else { return nil }
    var size = winsize()
    if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 { return Int(size.ws_col) }
    return Int(ProcessInfo.processInfo.environment["COLUMNS"] ?? "")
}

/// No border lines: columns line up by spacing and the header is dim. `shrink` lists columns to cut first, in order,
/// when the table is wider than the terminal; names stay whole.
struct Table {
    var header: [String]
    var rows: [[String]] = []
    var shrink: [Int] = []

    func render() -> [String] {
        let gap = 2
        var widths = header.indices.map { i in ([header[i]] + rows.map { $0[i] }).map(\.columns).max() ?? 0 }
        if let limit = terminalWidth {
            var over = widths.reduce(0, +) + gap * (widths.count - 1) - limit
            for i in shrink where over > 0 {
                let cut = min(over, max(0, widths[i] - 4))
                widths[i] -= cut
                over -= cut
            }
        }
        func line(_ cells: [String]) -> String {
            cells.indices.map { i in
                let cell = cells[i].truncated(to: widths[i])
                return i == cells.count - 1 ? cell : cell.padded(to: widths[i])
            }.joined(separator: String(repeating: " ", count: gap))
        }
        return [line(header).styled(.dim)] + rows.map(line)
    }

    func print() { render().forEach { say($0) } }
}
