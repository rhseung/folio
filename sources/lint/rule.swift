import SwiftSyntax

public struct Rule {
    public let name: String
    public let advice: String
    // strict 규칙에는 기준선이 없다. 규칙을 만들 때 모든 자리가 통과했으므로, `--update`를 주든 말든 걸리면 실패한다.
    public let strict: Bool
    let find: (Codebase) -> [Hit]

    init(name: String, strict: Bool = false, advice: String, find: @escaping (Codebase) -> [Hit]) {
        self.name = name
        self.strict = strict
        self.advice = advice
        self.find = find
    }

    public func hits(in code: Codebase) -> [Hit] { find(code) }
}
