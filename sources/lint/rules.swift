import SwiftSyntax

public enum Rules {
    public static var all: [Rule] {
        [
            viewWorkspaceCall, viewBodyLogic, uiString, layoutName, layer, restatingComment, docComment, designValue, designGrid,
            courseAccent, localFolders, appDirection, kindDefault, minuteTimeline, screenToolbar, launchEnvironment,
            kebabNames, folderSize, oneTypePerFile, actionPath,
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
    if path.hasPrefix("sources/app/app/debug/") { return true }
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
