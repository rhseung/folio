import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

public struct QueryMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard !protocols.isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): FolioActions.Query {}")]
    }

    public static func expansion(
        of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else { throw MacroError("@Query는 struct에만 붙입니다") }
        guard let list = node.arguments?.as(LabeledExprListSyntax.self) else { throw MacroError("@Query(\"<명령>\", \"<요약>\")") }
        var positional: [String] = []
        var named: [String: String] = [:]
        for arg in list {
            let source = arg.expression.trimmedDescription
            guard let label = arg.label?.text else { positional.append(source); continue }
            switch label {
            case "discussion", "examples", "phrases", "panel", "lines", "grades": named[label] = source
            case "cli":
                guard source != ".generated" else { break }
                named["generated"] = "false"
                if let call = arg.expression.as(FunctionCallExprSyntax.self),
                    let reason = call.arguments.first(where: { $0.label?.text == "reason" })
                {
                    named["manualReason"] = reason.expression.trimmedDescription
                }
            default: throw MacroError("모르는 인자입니다: \(label)")
            }
        }
        guard positional.count == 2 else { throw MacroError("@Query(\"<명령>\", \"<요약>\")") }
        let fields = try declaration.memberBlock.members.compactMap { try Field($0.decl) }
        for f in fields {
            if case .new = f.role { throw MacroError("읽기에는 새 항목이 없습니다: \(f.name)") }
            if f.patch { throw MacroError("읽기 입력은 Patch가 아닙니다: \(f.name)") }
            if f.wholeFile { throw MacroError("읽기 입력은 문서 전체가 아닙니다: \(f.name)") }
        }
        let specs = fields.map(\.spec).joined(separator: ",\n")
        return ActionMacro.codable(fields) + [
            """
            public static let spec = FolioActions.QuerySpec(command: \(raw: positional[0]), summary: \(raw: positional[1]), \
            discussion: \(raw: named["discussion"] ?? "\"\""), examples: \(raw: named["examples"] ?? "[]"), \
            phrases: \(raw: named["phrases"] ?? "[]"), generated: \(raw: named["generated"] ?? "true"), \
            manualReason: \(raw: named["manualReason"] ?? "nil"), panel: \(raw: named["panel"] ?? "false"), \
            lines: \(raw: named["lines"] ?? "false"), grades: \(raw: named["grades"] ?? "false"), \
            fields: [\n\(raw: specs)\n])
            """
        ]
    }
}
