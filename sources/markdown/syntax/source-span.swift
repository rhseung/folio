import Foundation

// 편집 보기가 확장 문법 하나에 칠할 범위다. 무슨 색과 굵기로 칠할지는 앱이 `kind`를 보고 정한다.
public struct SourceSpan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case listDash
        case blockID
        case escape
        case wikiLink(target: String)
        case footnote(definition: Bool)
    }

    public var kind: Kind
    public var range: NSRange
    // 흐리게 그리는 기호(`[[`, `]]`, `^id`)다.
    public var marks: [NSRange]
    // 이 범위가 코드(`tables`이면 표도)나 수식(`math`이면)과 겹치면 칠하지 않는다. nil이면 어디서나 칠한다.
    public var scope: NSRange?
    public var tables: Bool
    public var math: Bool

    init(_ kind: Kind, _ range: NSRange, marks: [NSRange] = [], scope: NSRange?, tables: Bool = true, math: Bool = false) {
        self.kind = kind
        self.range = range
        self.marks = marks
        self.scope = scope
        self.tables = tables
        self.math = math
    }
}
