import Foundation

// 콜아웃 종류 하나의 성질이다. 편집 보기의 색, 미리보기의 CSS, 번호, 증명 붙이기, 자동 완성, 안내문이 모두 이 값을 읽는다.
public struct CalloutKind: Hashable, Sendable {
    // 노트 색 토큰 `--c-<tone>`이다. 위젯도 같은 변수를 쓰므로 이름을 바꾸지 않는다. `neutral`은 증명처럼 바탕 없이 그린다.
    public enum Tone: String, CaseIterable, Sendable {
        case definition, theorem, example, warning, danger, neutral
    }

    public var name: String
    public var tone: Tone
    public var numbered: Bool
    // 바로 뒤의 `proof`가 이 콜아웃에 붙어 한 덩어리로 그려진다.
    public var provable: Bool

    public init(_ name: String, _ tone: Tone, numbered: Bool = false, provable: Bool = false) {
        self.name = name.lowercased()
        self.tone = tone
        self.numbered = numbered
        self.provable = provable
    }

    public static let proof = "proof"

    // 헤더 `[!종류]`로 쓸 수 없는 이름은 CSS 클래스로도 안전하지 않으므로 받지 않는다.
    public static func allows(_ name: String) -> Bool { name.wholeMatch(of: /[a-z-]+/) != nil }

    public var isDefault: Bool { Self.defaults.contains { $0.name == name } }

    public static let defaults: [CalloutKind] = [
        CalloutKind("definition", .definition, numbered: true),
        CalloutKind("theorem", .theorem, numbered: true, provable: true),
        CalloutKind("lemma", .theorem, numbered: true, provable: true),
        CalloutKind("corollary", .theorem, numbered: true, provable: true),
        CalloutKind("proposition", .theorem, provable: true),
        CalloutKind(proof, .neutral),
        CalloutKind("example", .example, numbered: true),
        CalloutKind("counterexample", .example, numbered: true),
        CalloutKind("remark", .neutral),
        CalloutKind("note", .definition),
        CalloutKind("tip", .example),
        CalloutKind("warning", .warning),
        CalloutKind("important", .warning),
        CalloutKind("question", .warning),
        CalloutKind("solution", .example),
        CalloutKind("summary", .example),
        CalloutKind("abstract", .definition),
        CalloutKind("info", .definition),
        CalloutKind("danger", .danger),
    ]
}
