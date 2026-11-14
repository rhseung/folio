import SwiftSyntax

extension Rules {
    static var designValue: Rule {
        Rule(
            name: "design-value", strict: true,
            advice: "take type sizes, colours and corner radii from Theme, or mark the line `// design: one-off, <why>`"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(under: "sources/app/features", "sources/app/app") {
                walk(Syntax(file.tree)) { node in
                    guard let found = rawDesignValue(node), !file.oneOff(found.at) else { return }
                    hits.append(Hit("design-value", file, file.line(of: found.at), found.what))
                }
            }
            return hits
        }
    }

    static var designGrid: Rule {
        Rule(
            name: "design-grid", strict: true,
            advice: "spacing, sizes and radii are multiples of 4, or of 2 where 4 is too coarse; "
                + "mark a real exception `// design: one-off, <why>`"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(under: "sources/app") {
                for token in file.tokens {
                    guard let found = gridValue(after: token), !file.oneOff(found.at) else { continue }
                    hits.append(Hit("design-grid", file, file.line(of: found.at), found.what))
                }
                for call in file.nodes(FunctionCallExprSyntax.self) {
                    guard let found = gridValue(in: call), !file.oneOff(found.at) else { continue }
                    hits.append(Hit("design-grid", file, file.line(of: found.at), found.what))
                }
            }
            return hits
        }
    }

    // tests/unit/app의 note bench는 accent만 정한 상태로 기준 이미지를 그렸으므로 tests/unit/app은 검사하지 않는다.
    static var courseAccent: Rule {
        Rule(
            name: "course-accent", strict: true,
            advice: "set a course's colour with .courseAccent(_:), not environment(\\.accent, …)"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(under: "sources/app") where !file.path.hasPrefix("sources/app/design/") {
                for call in file.nodes(FunctionCallExprSyntax.self) where calledName(call) == "environment" {
                    guard let path = call.arguments.first?.expression.as(KeyPathExprSyntax.self),
                        path.trimmedDescription == "\\.accent"
                    else { continue }
                    hits.append(Hit("course-accent", file, file.line(of: path), "environment(\\.accent"))
                }
            }
            return hits
        }
    }

    static let systemColors: Set<String> = [
        "red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue", "indigo", "purple", "pink", "brown", "gray",
        "white", "black",
    ]

    static func rawDesignValue(_ node: Syntax) -> (what: String, at: Syntax)? {
        if let call = node.as(FunctionCallExprSyntax.self), let first = call.arguments.first, let label = first.label {
            if calledName(call) == "system", call.calledExpression.is(MemberAccessExprSyntax.self), label.text == "size" {
                return (".system(size:", Syntax(label))
            }
            if calledName(call) == "Color", call.calledExpression.is(DeclReferenceExprSyntax.self),
                ["red", "white", "hue", "light"].contains(label.text)
            {
                return ("Color(\(label.text):", Syntax(label))
            }
        }
        if let argument = node.as(LabeledExprSyntax.self), let label = argument.label, label.text == "cornerRadius",
            let first = argument.expression.firstToken(viewMode: .sourceAccurate), first.isNumber
        {
            return ("cornerRadius: \(first.text)", Syntax(label))
        }
        if let token = node.as(TokenSyntax.self), case .integerLiteral(let text) = token.tokenKind, text.hasPrefix("0x"),
            text.dropFirst(2).filter(\.isHexDigit).count >= 6
        {
            return (text, node)
        }
        if let member = node.as(MemberAccessExprSyntax.self), systemColors.contains(member.declName.baseName.text) {
            let name = member.declName.baseName.text
            if let base = member.base {
                if base.as(DeclReferenceExprSyntax.self)?.baseName.text == "Color" { return ("Color.\(name)", node) }
            } else if let before = member.previousToken(viewMode: .sourceAccurate),
                [.leftParen, .colon, .comma, .infixQuestionMark, .postfixQuestionMark].contains(before.tokenKind),
                !isShadowBlack(member)
            {
                return (".\(name)", node)
            }
        }
        return nil
    }

    static func isShadowBlack(_ member: MemberAccessExprSyntax) -> Bool {
        guard member.declName.baseName.text == "black" else { return false }
        var current = member.parent
        while let node = current, !node.is(LabeledExprSyntax.self) { current = node.parent }
        guard let argument = current?.as(LabeledExprSyntax.self), argument.label?.text == "color",
            argument.expression.firstToken(viewMode: .sourceAccurate) == member.firstToken(viewMode: .sourceAccurate),
            let call = argument.parent?.parent?.as(FunctionCallExprSyntax.self)
        else { return false }
        return calledName(call) == "shadow"
    }

    static let gridLabels: Set<String> = [
        "spacing", "width", "height", "cornerRadius", "top", "leading", "bottom", "trailing", "minLength", "dx", "dy",
    ]

    static func gridValue(after token: TokenSyntax) -> (what: String, at: TokenSyntax)? {
        let lead: String
        switch token.tokenKind {
        case .identifier(let name) where gridLabels.contains(name):
            guard token.nextToken(viewMode: .sourceAccurate)?.tokenKind == .colon else { return nil }
            lead = "\(name): "
        case .identifier("CGFloat"):
            guard token.nextToken(viewMode: .sourceAccurate)?.tokenKind == .equal else { return nil }
            lead = "CGFloat = "
        default:
            return nil
        }
        guard let operand = token.nextToken(viewMode: .sourceAccurate)?.nextToken(viewMode: .sourceAccurate),
            let literal = offGridLiteral(at: operand)
        else { return nil }
        let sign = operand.tokenKind == .prefixOperator("-") ? "-" : ""
        return (lead + sign + literal.text, literal)
    }

    static func gridValue(in call: FunctionCallExprSyntax) -> (what: String, at: TokenSyntax)? {
        let arguments = Array(call.arguments)
        switch calledName(call) {
        case "padding":
            guard let last = arguments.last, last.label == nil,
                arguments.count == 1
                    || (arguments.count == 2 && arguments[0].label == nil
                        && arguments[0].expression.as(MemberAccessExprSyntax.self)?.base == nil),
                let literal = offGridNumber(last.expression)
            else { return nil }
            return ("padding(\(last.expression.trimmedDescription))", literal)
        case "CourseDot", "Avatar":
            guard let size = arguments.first(where: { $0.label?.text == "size" }),
                let literal = offGridNumber(size.expression)
            else { return nil }
            return ("size: \(size.expression.trimmedDescription)", literal)
        default:
            return nil
        }
    }

    static func offGridNumber(_ expression: ExprSyntax) -> TokenSyntax? {
        var expression = expression
        if let negative = expression.as(PrefixOperatorExprSyntax.self), negative.operator.text == "-" {
            expression = negative.expression
        }
        guard
            let literal = expression.as(IntegerLiteralExprSyntax.self)?.literal
                ?? expression.as(FloatLiteralExprSyntax.self)?.literal
        else { return nil }
        return offGridLiteral(at: literal)
    }

    static func offGridLiteral(at token: TokenSyntax) -> TokenSyntax? {
        var token = token
        if token.tokenKind == .prefixOperator("-"), let next = token.nextToken(viewMode: .sourceAccurate) { token = next }
        switch token.tokenKind {
        case .floatLiteral:
            return token
        case .integerLiteral(let text):
            guard let value = Int(text.filter { $0 != "_" }) else { return nil }
            return value % 2 == 1 && value != 1 ? token : nil
        default:
            return nil
        }
    }

    static func calledName(_ call: FunctionCallExprSyntax) -> String? {
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) { return member.declName.baseName.text }
        return call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
    }
}

extension SourceFile {
    func oneOff(_ node: some SyntaxProtocol) -> Bool { lines[line(of: node) - 1].contains("design: one-off") }
}

extension TokenSyntax {
    var isNumber: Bool {
        switch tokenKind {
        case .integerLiteral, .floatLiteral: true
        default: false
        }
    }
}
