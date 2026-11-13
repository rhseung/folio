import Foundation
import SwiftSyntax

// AGENTS.md "이름과 주석": a comment says what the code can't. Only the plain case is mechanical: a one-line comment
// whose every word is already in the name under it. The rest is the review's.
extension Rules {
    static var restatingComment: Rule {
        Rule(
            name: "restating-comment",
            advice: "a comment says why the code is this way; drop one that only names what the declaration under it already says"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(
                under: "app", "packages/folio-core/sources", "packages/folio-markdown/sources",
                "packages/folio-ai/sources")
            // An @Action field's `///` is its CLI help.
            where !file.path.contains("/generated/") && !file.path.contains("/folio-actions/") {
                walk(Syntax(file.tree)) { node in
                    guard let keyword = declarationKeyword(node), let first = node.firstToken(viewMode: .sourceAccurate),
                        let comment = loneComment(before: first), restates(comment, file.restOfLine(after: keyword))
                    else { return }
                    hits.append(Hit("restating-comment", file, file.line(of: first) - 1, comment))
                }
            }
            return hits
        }
    }

    static func declarationKeyword(_ node: Syntax) -> TokenSyntax? {
        if let declaration = node.as(VariableDeclSyntax.self) { return declaration.bindingSpecifier }
        if let declaration = node.as(FunctionDeclSyntax.self) { return declaration.funcKeyword }
        if let declaration = node.as(StructDeclSyntax.self) { return declaration.structKeyword }
        if let declaration = node.as(ClassDeclSyntax.self) { return declaration.classKeyword }
        if let declaration = node.as(EnumDeclSyntax.self) { return declaration.enumKeyword }
        if let declaration = node.as(ActorDeclSyntax.self) { return declaration.actorKeyword }
        if let declaration = node.as(ProtocolDeclSyntax.self) { return declaration.protocolKeyword }
        if let declaration = node.as(EnumCaseDeclSyntax.self) { return declaration.caseKeyword }
        if let declaration = node.as(TypeAliasDeclSyntax.self) { return declaration.typealiasKeyword }
        if let declaration = node.as(InitializerDeclSyntax.self) { return declaration.initKeyword }
        if let declaration = node.as(SubscriptDeclSyntax.self) { return declaration.subscriptKeyword }
        return nil
    }

    // A comment run of more than one line explains something, so only a lone line counts: on its own line, with no
    // comment line just above it and no blank line before the declaration.
    static func loneComment(before token: TokenSyntax) -> String? {
        let pieces = Array(token.leadingTrivia.pieces)
        var index = pieces.count - 1
        func skipBlanks() { while index >= 0, pieces[index].isBlank { index -= 1 } }
        skipBlanks()
        guard index >= 0, pieces[index].newlineCount == 1 else { return nil }
        index -= 1
        skipBlanks()
        guard index >= 0, let text = pieces[index].lineCommentText else { return nil }
        index -= 1
        skipBlanks()
        if index >= 0 {
            guard pieces[index].newlineCount > 0 else { return nil }
            if pieces[index].newlineCount == 1 {
                index -= 1
                skipBlanks()
                if index >= 0, pieces[index].lineCommentText != nil { return nil }
            }
        }
        let body = text.drop { $0 == "/" }
        return String(body.drop(while: \.isWhitespace)).trimmingCharacters(in: .whitespaces)
    }

    static func restates(_ comment: String, _ declaration: String) -> Bool {
        let said = words(comment).subtracting(filler)
        // A code span or a symbol says something the name can't, such as the syntax a case stands for.
        let symbols = Set("`\\[]<>/=+*#@$%^&|~")
        let tags = ["MARK", "TODO", "FIXME", "swiftlint", "design:", "strings:"]
        guard !said.isEmpty, !hasHangul(comment), !comment.contains(where: symbols.contains),
            !tags.contains(where: { comment.hasPrefix($0) })
        else { return false }
        return said.isSubset(of: words(String(declaration.prefix(120))))
    }

    static let filler: Set<String> = [
        "a", "an", "the", "of", "for", "to", "in", "on", "is", "are", "this", "that", "its", "it", "and", "or", "with", "by",
        "from", "returns", "return", "gets", "get", "sets", "set", "current", "given", "value", "property", "function",
        "method", "initializer", "init", "creates", "create", "type", "struct", "class", "enum", "view", "model", "var",
        "let", "func",
    ]

    // `courseTitle` and "course titles" both give {course, title, titles}.
    static func words(_ text: String) -> Set<String> {
        var spaced = ""
        var previous: Character?
        for character in text {
            if let previous, previous.isASCII, previous.isLowercase || previous.isNumber, character.isASCII,
                character.isUppercase
            {
                spaced.append(" ")
            }
            spaced.append(character)
            previous = character
        }
        var found: Set<String> = []
        for run in spaced.lowercased().split(whereSeparator: { !($0.isASCII && $0.isLetter) }) {
            let word = String(run)
            found.insert(word)
            if word.hasSuffix("s"), word.count > 3 { found.insert(String(word.dropLast())) }
        }
        return found
    }
}

extension SourceFile {
    func restOfLine(after token: TokenSyntax) -> String {
        let end = token.endPositionBeforeTrailingTrivia
        let line = line(of: end)
        let rest = lines[line - 1].utf8.dropFirst(end.utf8Offset - lineStart(line))
        return String(decoding: rest, as: UTF8.self)
    }
}
