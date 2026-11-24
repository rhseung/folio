import Foundation

public struct CalloutHeader: Hashable, Sendable {
    public var type: String
    public var title: String
    public var folded: Bool

    static var pattern: Regex<(Substring, Substring, Substring, Substring)> { #/^\[!([A-Za-z-]+)\]([+-]?)[ \t]*(.*)$/# }

    public init?(line: String) {
        guard let m = line.wholeMatch(of: CalloutHeader.pattern) else { return nil }
        type = m.1.lowercased()
        folded = m.2 == "-"
        title = String(m.3)
    }

    // 번호 뒤에 낱말 문자나 `-`가 오면 번호가 아니다. `\b`로 끊으면 "2-connected", "3-regular"처럼 숫자로 시작하는 제목의 숫자를
    // 번호로 떼어 낸다. "1.2: Hall", "2.3. Menger"처럼 번호 뒤에 붙인 쌍점과 마침표는 받는다.
    public var explicitNumber: String? {
        title.firstMatch(of: /^(?:[A-Za-z]+\s+)?(\d+(?:\.\d+)*)(?![\w-]|\.\d)/).map { String($0.1) }
    }

    public var titleWithoutNumber: String {
        guard let explicit = explicitNumber else { return title }
        let pattern = #"^(?:[A-Za-z]+\s+)?"# + NSRegularExpression.escapedPattern(for: explicit) + #"[.:]?\s*"#
        return title.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}
