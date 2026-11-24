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

    // 번호 뒤에 공백이나 줄 끝이 와야 번호다. `\b`로 끊으면 "2-connected", "3-regular"처럼 숫자로 시작하는 제목의 숫자를 번호로 떼어 낸다.
    public var explicitNumber: String? {
        title.firstMatch(of: /^(?:[A-Za-z]+\s+)?(\d+(?:\.\d+)*)(?=\s|$)/).map { String($0.1) }
    }
}
