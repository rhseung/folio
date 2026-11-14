import Foundation

public struct CompletionQuery: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case slash
        case callout
        case codeLanguage
        case texCommand
        case texEnvironment
        case snippet
        case asciiMath
        case link(LinkQuery)
    }

    public let kind: Kind
    public let text: String
    public let range: NSRange
    public let place: SourcePlace

    // 저절로 열린 메뉴(맨 펜스, 스니펫 트리거)에서 Return이 후보를 고르면 언어 없는 펜스나 `->`로 끝나는 줄을 끝낼 수
    // 없다. 그래서 이때 Return은 줄바꿈이고 Tab만 후보를 고른다.
    public var takesReturn: Bool {
        switch kind {
        case .snippet, .asciiMath: false
        case .codeLanguage: !text.isEmpty
        default: true
        }
    }

    public func continues(_ other: CompletionQuery) -> Bool {
        guard range.location == other.range.location else { return false }
        if case .link(let a) = kind, case .link(let b) = other.kind { return a.part == b.part && a.target == b.target }
        return kind == other.kind
    }
}

extension CompletionQuery {
    func widened(by n: Int) -> CompletionQuery {
        CompletionQuery(kind: kind, text: text, range: NSRange(location: range.location - n, length: range.length + n), place: place)
    }

    public func shifted(by n: Int) -> CompletionQuery {
        CompletionQuery(kind: kind, text: text, range: NSRange(location: range.location + n, length: range.length), place: place)
    }
}
