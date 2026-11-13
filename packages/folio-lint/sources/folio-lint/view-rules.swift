import SwiftSyntax

// AGENTS.md "화면: 모델과 뷰": a view lays out what its model gives it.
extension Rules {
    static var viewWorkspaceCall: Rule {
        Rule(
            name: "view-workspace-call",
            advice: "a view reads its model; put the call behind a model property or method (AGENTS.md \"화면: 모델과 뷰\")"
        ) { code in
            let files = code.files(under: "app/features")
            let views = viewNames(files)
            var hits: [Hit] = []
            for file in files {
                for call in file.nodes(FunctionCallExprSyntax.self) {
                    guard let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base,
                        let workspace = workspaceToken(base), inView(call, views)
                    else { continue }
                    hits.append(
                        Hit(
                            "view-workspace-call", file, file.line(of: workspace),
                            "workspace.\(member.declName.baseName.text)("))
                }
            }
            return hits
        }
    }

    static var viewBodyLogic: Rule {
        Rule(
            name: "view-body-logic",
            advice: "group, filter, sort and count in the model (or FolioDomain for a data rule) and give the view the result"
        ) { code in
            let files = code.files(under: "app/features")
            let views = viewNames(files)
            var hits: [Hit] = []
            for file in files {
                for call in file.nodes(FunctionCallExprSyntax.self) {
                    guard let found = sortingOrCounting(call), let member = viewMember(around: call),
                        inView(call, views)
                    else { continue }
                    hits.append(Hit("view-body-logic", file, file.line(of: found.at), "\(member): \(found.what)"))
                }
            }
            return hits
        }
    }

    // A view's helpers often sit in an extension in another file, so the names come from every file first.
    static func viewNames(_ files: [SourceFile]) -> Set<String> {
        var names: Set<String> = []
        for file in files {
            for view in file.nodes(StructDeclSyntax.self) where conformsToView(view.inheritanceClause) {
                names.insert(view.name.text)
            }
        }
        return names
    }

    static func conformsToView(_ clause: InheritanceClauseSyntax?) -> Bool {
        clause?.inheritedTypes.contains { inherited in
            let name = inherited.type.trimmedDescription.split(separator: ".").last.map(String.init)
            return name == "View" || name == "ViewModifier"
        } ?? false
    }

    static func inView(_ node: some SyntaxProtocol, _ views: Set<String>) -> Bool {
        var current = node.parent
        while let ancestor = current {
            if let type = ancestor.as(StructDeclSyntax.self), views.contains(type.name.text) { return true }
            if let ext = ancestor.as(ExtensionDeclSyntax.self),
                views.contains(ext.extendedType.trimmedDescription) || conformsToView(ext.inheritanceClause)
            {
                return true
            }
            current = ancestor.parent
        }
        return false
    }

    // `model.workspace` is the same reach past the model as `workspace` itself.
    static func workspaceToken(_ base: ExprSyntax) -> TokenSyntax? {
        if let reference = base.as(DeclReferenceExprSyntax.self), reference.baseName.text == "workspace" {
            return reference.baseName
        }
        if let access = base.as(MemberAccessExprSyntax.self), access.declName.baseName.text == "workspace" {
            return access.declName.baseName
        }
        return nil
    }

    static func sortingOrCounting(_ call: FunctionCallExprSyntax) -> (what: String, at: TokenSyntax)? {
        let label = call.arguments.first?.label?.text
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            let name = member.declName.baseName
            switch name.text {
            case "filter", "reduce", "sorted", "partition": return ("." + name.text, name)
            // `count` alone is a property read, and `min()` of comparable values is no rule; only the closure forms are.
            case "count": return label == "where" ? (".count(where", name) : nil
            case "min", "max": return label == "by" ? (".\(name.text)(by", name) : nil
            default: return nil
            }
        }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self), reference.baseName.text == "Dictionary",
            label == "grouping"
        {
            return ("Dictionary(grouping", reference.baseName)
        }
        return nil
    }

    // The innermost `some View` member around the node: `body` or one of its pieces.
    static func viewMember(around node: some SyntaxProtocol) -> String? {
        var current = node.parent
        while let ancestor = current {
            if let variable = ancestor.as(VariableDeclSyntax.self) {
                for binding in variable.bindings where binding.accessorBlock != nil && isSomeView(binding.typeAnnotation?.type) {
                    return binding.pattern.trimmedDescription
                }
            }
            if let function = ancestor.as(FunctionDeclSyntax.self), function.body != nil,
                isSomeView(function.signature.returnClause?.type)
            {
                return function.name.text
            }
            current = ancestor.parent
        }
        return nil
    }

    static func isSomeView(_ type: TypeSyntax?) -> Bool {
        guard let opaque = type?.as(SomeOrAnyTypeSyntax.self), opaque.someOrAnySpecifier.text == "some" else { return false }
        let name = opaque.constraint.trimmedDescription
        return name == "View" || name == "SwiftUI.View"
    }
}
