import Foundation
import SwiftSyntax

extension Rules {
    static var restatingComment: Rule {
        Rule(
            name: "restating-comment",
            advice: "a comment says why the code is this way; drop one that only names what the declaration under it already says"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(
                under: "sources", except: "sources/lint", "sources/lint-command")
            where !file.path.contains("/generated/") && !file.path.hasPrefix("sources/actions/") {
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

extension Rules {
    static var docComment: Rule {
        Rule(
            name: "doc-comment", strict: true,
            advice: "`///` is only for an @Action field's CLI help; drop the comment, or keep why the code must be this way as `//`"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(under: "sources", "tests") {
                for token in file.tokens {
                    for comment in docComments(around: token) where !(comment.leading && isActionField(token)) {
                        hits.append(Hit("doc-comment", file, file.line(of: comment.position), comment.text))
                    }
                }
            }
            return hits
        }
    }

    struct DocComment {
        let text: String
        let position: AbsolutePosition
        let leading: Bool
    }

    static func docComments(around token: TokenSyntax) -> [DocComment] {
        var found: [DocComment] = []
        for leading in [true, false] {
            var offset = leading ? token.position : token.endPositionBeforeTrailingTrivia
            for piece in leading ? token.leadingTrivia.pieces : token.trailingTrivia.pieces {
                if let text = piece.docText { found.append(DocComment(text: text, position: offset, leading: leading)) }
                offset = offset.advanced(by: piece.sourceLength.utf8Length)
            }
        }
        return found
    }

    // 매크로는 `@Action` 타입 바로 안에 선언한 stored property의 leading trivia를 읽는다.
    static func isActionField(_ token: TokenSyntax) -> Bool {
        guard let field = token.parent?.ancestorOrSelf(VariableDeclSyntax.self), field.firstToken(viewMode: .sourceAccurate) == token,
            let group = field.parent?.parent?.parent?.parent?.asProtocol(DeclGroupSyntax.self)
        else { return false }
        return group.attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Action" }
    }
}

extension TriviaPiece {
    var docText: String? {
        switch self {
        case .docLineComment(let text), .docBlockComment(let text): text
        default: nil
        }
    }
}

extension Syntax {
    func ancestorOrSelf<Node: SyntaxProtocol>(_ type: Node.Type) -> Node? {
        var current: Syntax? = self
        while let node = current {
            if let found = node.as(type) { return found }
            current = node.parent
        }
        return nil
    }
}
