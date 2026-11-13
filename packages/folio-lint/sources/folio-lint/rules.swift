import SwiftSyntax

public struct Hit: Hashable, Sendable {
    public let check: String
    public let path: String
    public let line: Int
    // The baseline matches places by this, not by line, so a place keeps its entry when lines above it move.
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
    // A strict rule has no baseline: every place passed it when it was written, so any hit fails, `--update` or not.
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
            viewWorkspaceCall, viewBodyLogic, uiString, layoutName, layer, restatingComment, designValue, designGrid,
            courseAccent, localFolders, appDirection, kindDefault, minuteTimeline, screenToolbar, launchEnvironment,
            kebabNames, folderSize,
        ]
    }
}

// MARK: Exemptions

extension SourceFile {
    // Code the shipped app never runs: `#if DEBUG` and `#Preview`. A `#if DEBUG … #else` leaves the `#else` checked.
    func debugOnly(_ node: some SyntaxProtocol) -> Bool {
        var current = node.parent
        while let ancestor = current {
            if let clause = ancestor.as(IfConfigClauseSyntax.self), clause.poundKeyword.tokenKind == .poundIf,
               clause.condition?.trimmedDescription == "DEBUG" {
                return true
            }
            if let macro = ancestor.as(MacroExpansionDeclSyntax.self), macro.macroName.text == "Preview" { return true }
            if let macro = ancestor.as(MacroExpansionExprSyntax.self), macro.macroName.text == "Preview" { return true }
            current = ancestor.parent
        }
        return false
    }

    // `// strings: data, <why>` covers its line up to the mark, and the whole block or literal when the line opens one:
    // a keyword list is long, and marking each of its lines would bury the list.
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
    // Interpolated code is left out: `"\(count) items"` is the copy " items".
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
