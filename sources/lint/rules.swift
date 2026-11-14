import SwiftSyntax

public struct Hit: Hashable, Sendable {
    public let check: String
    public let path: String
    public let line: Int
    // 기준선은 줄이 아니라 이 값으로 자리를 맞춘다. 그래서 위의 줄이 움직여도 자리가 자기 항목을 유지한다.
    public let key: String

    init(_ check: String, _ file: SourceFile, _ line: Int, _ key: String) {
        self.init(check, path: file.path, line, key)
    }

    init(_ check: String, path: String, _ line: Int, _ key: String) {
        self.check = check
        self.path = path
        self.line = line
        self.key = key.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public var entry: String { "\(check)\t\(path)\t\(key)" }
}

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

public enum Rules {
    public static var all: [Rule] {
        [
            viewWorkspaceCall, viewBodyLogic, uiString, layoutName, layer, restatingComment, docComment, designValue, designGrid,
            courseAccent, localFolders, appDirection, kindDefault, minuteTimeline, screenToolbar, launchEnvironment,
            kebabNames, folderSize,
        ]
    }
}

// MARK: Exemptions

extension SourceFile {
    func debugOnly(_ node: some SyntaxProtocol) -> Bool {
        var current = node.parent
        while let ancestor = current {
            if let clause = ancestor.as(IfConfigClauseSyntax.self), clause.poundKeyword.tokenKind == .poundIf,
                clause.condition?.trimmedDescription == "DEBUG"
            {
                return true
            }
            if let macro = ancestor.as(MacroExpansionDeclSyntax.self), macro.macroName.text == "Preview" { return true }
            if let macro = ancestor.as(MacroExpansionExprSyntax.self), macro.macroName.text == "Preview" { return true }
            current = ancestor.parent
        }
        return false
    }

    func dataMarks() -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for token in tokens where token.trailingTrivia.pieces.contains(where: { $0.lineCommentText.map(isDataMark) ?? false }) {
            let end = token.endPositionBeforeTrailingTrivia
            let start = lineStart(line(of: end))
            ranges.append(start..<end.utf8Offset)
            if [.leftBrace, .leftSquare, .leftParen].contains(token.tokenKind), let opened = token.parent {
                ranges.append(start..<opened.endPositionBeforeTrailingTrivia.utf8Offset)
            }
        }
        return ranges
    }
}

private func isDataMark(_ comment: String) -> Bool {
    let text = comment.drop { $0 == "/" }.drop(while: \.isWhitespace)
    guard text.hasPrefix("strings: data") else { return false }
    return text.dropFirst("strings: data".count).first.map { !$0.isLetter && !$0.isNumber } ?? true
}

func isDebugFile(_ path: String) -> Bool {
    let name = path.split(separator: "/").last.map(String.init) ?? path
    return name.hasPrefix("debug-") || name.hasSuffix("-snapshots.swift")
}

extension TriviaPiece {
    var lineCommentText: String? {
        switch self {
        case .lineComment(let text), .docLineComment(let text): text
        default: nil
        }
    }

    var newlineCount: Int {
        switch self {
        case .newlines(let count), .carriageReturns(let count), .carriageReturnLineFeeds(let count): count
        default: 0
        }
    }

    var isBlank: Bool {
        switch self {
        case .spaces, .tabs: true
        default: false
        }
    }
}

extension StringLiteralExprSyntax {
    var plainText: String {
        segments.map { segment in
            if case .stringSegment(let text) = segment { return text.content.text }
            return ""
        }.joined()
    }
}

func hasHangul(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
}
