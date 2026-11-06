import Foundation

/// One error or warning from a TeX build, located in a file when the engine said where.
public struct TexIssue: Equatable, Sendable, Codable {
    public enum Severity: String, Equatable, Sendable, Codable { case error, warning }

    public var severity: Severity
    public var file: String?
    public var line: Int?
    public var message: String

    public init(_ severity: Severity, file: String? = nil, line: Int? = nil, message: String) {
        self.severity = severity
        self.file = file
        self.line = line
        self.message = message
    }

    public var description: String {
        guard let file else { return message }
        return line.map { "\(file):\($0): \(message)" } ?? "\(file): \(message)"
    }
}

public enum TexLog {
    /// Reads Tectonic's console output, which names each problem as `error: hw.tex:5: Undefined control sequence`.
    /// The TeX log itself is not read: its `l.5` lines don't say which `\input` file they belong to.
    /// An unlocated error is kept only when no located one came, because Tectonic follows every real error
    /// with generic ones ("the XeTeX engine had an unrecoverable error").
    ///
    /// Builds keep going past errors so all of them show at once, which repeats them: TeX runs again when the `.aux`
    /// changed, and one broken line (a missing package) can raise the same error dozens of times. Each is kept once.
    public static func issues(_ output: String) -> [TexIssue] {
        var located: [TexIssue] = []
        var general: [TexIssue] = []
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let severity: TexIssue.Severity
            let rest: Substring
            if line.hasPrefix("error: ") {
                severity = .error
                rest = line.dropFirst(7)
            } else if line.hasPrefix("warning: ") {
                severity = .warning
                rest = line.dropFirst(9)
            } else {
                continue
            }
            // Tectonic's own note that it went past errors. Kept as one, so a build whose errors didn't print as
            // `error:` lines still counts as failed and its PDF, with parts left out, is not placed.
            if severity == .warning, rest.hasPrefix("errors were issued by the TeX engine") {
                general.append(TexIssue(.error, message: String(rest)))
            } else if let issue = parseLocated(severity, rest) {
                located.append(issue)
            } else if severity == .error {
                general.append(TexIssue(.error, message: String(rest)))
            }
        }
        located = located.uniqued()
        let errors = located.filter { $0.severity == .error }
        return errors.isEmpty ? general.prefix(1) + located : located
    }

    /// `file:line: message`. A file name may hold colons, so the line number is the first all-digit field.
    private static func parseLocated(_ severity: TexIssue.Severity, _ rest: Substring) -> TexIssue? {
        let parts = rest.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        for i in 1..<(parts.count - 1) {
            if let n = Int(parts[i]), n > 0 {
                let file = parts[..<i].joined(separator: ":")
                // TeX's own `! LaTeX Error:` keeps its bang when Tectonic passes it on.
                var message = parts[(i + 1)...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
                if message.hasPrefix("! ") { message.removeFirst(2) }
                guard !file.isEmpty, !message.isEmpty else { return nil }
                return TexIssue(severity, file: file, line: n, message: message)
            }
        }
        return nil
    }
}

private extension Array where Element == TexIssue {
    func uniqued() -> [TexIssue] {
        var seen: [TexIssue] = []
        for issue in self where !seen.contains(issue) { seen.append(issue) }
        return seen
    }
}
