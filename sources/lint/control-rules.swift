import SwiftSyntax

extension Rules {
    static let systemControls: Set<String> = ["Toggle", "Picker", "TextField"]

    static let systemButtonStyles: Set<String> = [
        "plain", "borderless", "bordered", "borderedProminent", "link", "automatic", "accessoryBar", "accessoryBarAction",
    ]

    static let systemButtonStyleTypes: Set<String> = [
        "PlainButtonStyle", "BorderlessButtonStyle", "BorderedButtonStyle", "BorderedProminentButtonStyle", "LinkButtonStyle",
        "DefaultButtonStyle",
    ]

    // 메뉴와 오른쪽 클릭 메뉴의 내용은 시스템이 그리므로 그 안의 `Toggle`과 `Picker`는 체크 표시 항목이 된다(docs/DESIGN.md
    // "시스템 컨트롤 대신 쓰는 것"). `.pill(width:)`을 붙인 `TextField`는 그 자체가 짧은 값의 원자다.
    static var designControl: Rule {
        Rule(
            name: "design-control",
            advice: "a feature draws controls with the atoms in app/design/atoms (Switch, ChoiceMenu, Segmented, InlineField, "
                + "`.pill`, `.ghost`, `.pointing`, `.menuButton`), not the system Toggle, Picker, TextField and button styles, "
                + "and doesn't declare its own ButtonStyle (docs/DESIGN.md \"층\")"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(under: "sources/app/features") where !isDebugFile(file.path) {
                for call in file.nodes(FunctionCallExprSyntax.self) where !file.debugOnly(call) {
                    if let found = systemControl(call) {
                        hits.append(Hit("design-control", file, file.line(of: call), found))
                    }
                }
                for decl in file.nodes(StructDeclSyntax.self) where !file.debugOnly(decl) {
                    let inherited = decl.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
                    guard inherited.contains(where: { $0 == "ButtonStyle" || $0 == "PrimitiveButtonStyle" }) else { continue }
                    hits.append(Hit("design-control", file, file.line(of: decl.name), "ButtonStyle \(decl.name.text)"))
                }
            }
            return hits
        }
    }

    static func systemControl(_ call: FunctionCallExprSyntax) -> String? {
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            guard systemControls.contains(name), !inMenuContent(call) else { return nil }
            if name == "TextField", chained(call).contains("pill") { return nil }
            return "\(name)("
        }
        guard calledName(call) == "buttonStyle", call.calledExpression.is(MemberAccessExprSyntax.self),
            let style = call.arguments.first?.expression
        else { return nil }
        if let member = style.as(MemberAccessExprSyntax.self), member.base == nil,
            systemButtonStyles.contains(member.declName.baseName.text)
        {
            return ".buttonStyle(.\(member.declName.baseName.text))"
        }
        if let made = style.as(FunctionCallExprSyntax.self), let type = made.calledExpression.as(DeclReferenceExprSyntax.self),
            systemButtonStyleTypes.contains(type.baseName.text)
        {
            return ".buttonStyle(\(type.baseName.text)())"
        }
        return nil
    }

    // `TextField(…).pill(width:)`처럼 이 호출 뒤에 이어 붙인 수정자의 이름들.
    static func chained(_ call: FunctionCallExprSyntax) -> [String] {
        var names: [String] = []
        var current = Syntax(call)
        while let member = current.parent?.as(MemberAccessExprSyntax.self), member.base.map(Syntax.init) == current,
            let next = member.parent?.as(FunctionCallExprSyntax.self)
        {
            names.append(member.declName.baseName.text)
            current = Syntax(next)
        }
        return names
    }

    static func inMenuContent(_ node: some SyntaxProtocol) -> Bool {
        var current = node.parent
        while let ancestor = current {
            if let closure = ancestor.as(ClosureExprSyntax.self), let owner = menuOwner(of: closure) {
                return ["Menu", "contextMenu"].contains(owner)
            }
            current = ancestor.parent
        }
        return false
    }

    // 클로저가 어느 호출의 내용인지. 메뉴의 `label:`은 메뉴의 내용이 아니라 단추의 모양이므로 빼고, 바깥 클로저를 본다.
    static func menuOwner(of closure: ClosureExprSyntax) -> String? {
        if let call = closure.parent?.as(FunctionCallExprSyntax.self), call.trailingClosure == closure,
            let name = calledName(call), ["Menu", "contextMenu"].contains(name)
        {
            return name
        }
        if let argument = closure.parent?.as(LabeledExprSyntax.self), argument.label?.text != "label",
            let call = argument.parent?.parent?.as(FunctionCallExprSyntax.self), let name = calledName(call),
            ["Menu", "contextMenu"].contains(name)
        {
            return name
        }
        return nil
    }
}
