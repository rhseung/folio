import Foundation

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

// 지금 시각이 아니라 달력 날짜의 자정을 `SOURCE_DATE_EPOCH`로 쓴다. 그래야 같은 날 바뀌지 않은 글을 다시 빌드하면
// 같은 바이트가 나와서 iCloud가 새로 동기화할 것이 없다.
public enum TexBuildTime {
    public static func sourceDateEpoch(at now: Date, calendar: Calendar) -> Int {
        Int(calendar.startOfDay(for: now).timeIntervalSince1970)
    }
}

public enum TexLog {
    // TeX 로그의 `l.5` 줄은 어느 `\input` 파일의 줄인지 알려 주지 않으므로 Tectonic의 콘솔 출력을 읽는다. Tectonic은
    // 실제 오류마다 일반적인 오류를 뒤에 붙이므로, 위치 없는 오류는 위치 있는 오류가 없을 때만 남긴다. `.aux`가 바뀌면
    // TeX가 다시 돌아 같은 오류가 수십 번 나오므로, 오류마다 한 번만 남긴다.
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
            // Tectonic이 오류를 넘기고 계속 빌드했다는 메모다. 이 메모를 하나로 남겨야 오류가 `error:` 줄로 찍히지 않은
            // 빌드도 실패로 세고, 일부가 빠진 PDF를 두지 않는다.
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

    // 파일 이름에 콜론이 들어갈 수 있으므로, 모두 숫자인 첫 칸을 줄 번호로 본다.
    private static func parseLocated(_ severity: TexIssue.Severity, _ rest: Substring) -> TexIssue? {
        let parts = rest.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        for i in 1..<(parts.count - 1) {
            if let n = Int(parts[i]), n > 0 {
                let file = parts[..<i].joined(separator: ":")
                // Tectonic이 넘겨준 TeX의 `! LaTeX Error:`는 앞의 느낌표를 그대로 지닌다.
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
