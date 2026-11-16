import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

public struct ActionMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard !protocols.isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): FolioActions.Action {}")]
    }

    public static func expansion(
        of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else { throw MacroError("@Action은 struct에만 붙입니다") }
        let args = try Arguments(node)
        let fields = try declaration.memberBlock.members.compactMap { try Field($0.decl) }
        let names = Set(fields.map(\.name))
        for (label, template) in [("confirm", args.confirmText), ("done", args.doneText)] {
            for p in placeholders(template ?? "") where !names.contains(p) {
                throw MacroError("\(label)의 {\(p)}에 맞는 필드가 없습니다")
            }
        }
        if ["removes", "moves"].contains(args.effect), args.confirm == nil {
            throw MacroError("지우거나 옮기는 액션(.\(args.effect))은 confirm:으로 확인 문구를 줘야 합니다")
        }

        let specs = fields.map(\.spec).joined(separator: ",\n")
        let wholeFiles = fields.filter(\.wholeFile)
        guard wholeFiles.count <= 1 else { throw MacroError("@WholeFile은 액션에 하나만 둡니다") }
        let current: [DeclSyntax] = wholeFiles.map { f in
            """
            public static func currentFile(_ ctx: FolioActions.ActionContext) throws -> (field: String, value: FolioCore.JSONValue)? {
            (\(raw: f.quoted(f.name)), try FolioCore.JSONValue(\(raw: f.base).current(in: ctx)))
            }
            """
        }
        return current + codable(fields) + [
            """
            public static let spec = FolioActions.ActionSpec(command: \(raw: args.command), summary: \(raw: args.summary), discussion: \(raw: args.discussion), \
            effect: .\(raw: args.effect), confirm: \(raw: args.confirm ?? "nil"), done: \(raw: args.done), examples: \(raw: args.examples), \
            phrases: \(raw: args.phrases), generated: \(raw: args.generated), manualReason: \(raw: args.manualReason ?? "nil"), \
            undoable: \(raw: args.undoable), proposal: \(raw: args.proposal ?? "nil"), panel: \(raw: args.panel), fields: [\n\(raw: specs)\n])
            """
        ]
    }

    static func codable(_ fields: [Field]) -> [DeclSyntax] {
        let keys = fields.map(\.name).joined(separator: ", ")
        let params = fields.map { f in "\(f.name): \(f.type)" + (f.parameterDefault.map { " = \($0)" } ?? "") }.joined(separator: ", ")
        let assigns = fields.map { "self.\($0.name) = \($0.name)" }.joined(separator: "\n")
        let decodes = fields.map { "self.\($0.name) = \($0.decode)" }.joined(separator: "\n")
        let encodes = fields.map(\.encode).joined(separator: "\n")
        return [
            fields.isEmpty
                ? "public enum CodingKeys: String, CodingKey { case _none }"
                : "public enum CodingKeys: String, CodingKey { case \(raw: keys) }",
            "public init(\(raw: params)) {\n\(raw: assigns)\n}",
            "public init(from decoder: any Decoder) throws {\nlet c = try decoder.container(keyedBy: CodingKeys.self)\n\(raw: fields.isEmpty ? "_ = c" : decodes)\n}",
            "public func encode(to encoder: any Encoder) throws {\nvar c = encoder.container(keyedBy: CodingKeys.self)\n\(raw: fields.isEmpty ? "_ = c" : encodes)\n}",
        ]
    }

    static func placeholders(_ text: String) -> [String] {
        var out: [String] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out.append(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return out
    }
}

private struct Arguments {
    var command = "", summary = "", discussion = "\"\"", effect = "changes", confirm: String?, done = "", examples = "[]", phrases = "[]"
    var generated = "true", manualReason: String?, undoable = "false", proposal: String?, panel = "false"
    var confirmText: String?, doneText: String?

    init(_ node: AttributeSyntax) throws {
        guard let list = node.arguments?.as(LabeledExprListSyntax.self) else { throw MacroError("@Action(\"<명령>\", \"<요약>\", done: ...)") }
        var positional: [String] = []
        for arg in list {
            let source = arg.expression.trimmedDescription
            switch arg.label?.text {
            case nil: positional.append(source)
            case "discussion": discussion = source
            case "effect": effect = String(source.drop { $0 == "." })
            case "confirm":
                confirm = source
                confirmText = literal(arg.expression)
            case "done":
                done = source
                doneText = literal(arg.expression)
            case "examples": examples = source
            case "phrases": phrases = source
            case "cli":
                guard source != ".generated" else { break }
                generated = "false"
                // spec이 같은 literal을 갖도록 `.manual(reason: "...")`의 이유를 쓴 그대로 옮긴다.
                if let call = arg.expression.as(FunctionCallExprSyntax.self),
                    let reason = call.arguments.first(where: { $0.label?.text == "reason" })
                {
                    manualReason = reason.expression.trimmedDescription
                }
            case "undoable": undoable = source
            case "proposal": proposal = source
            case "panel": panel = source
            case let other?: throw MacroError("모르는 인자입니다: \(other)")
            }
        }
        guard positional.count == 2, !done.isEmpty else { throw MacroError("@Action(\"<명령>\", \"<요약>\", done: \"<완료 문구>\")") }
        (command, summary) = (positional[0], positional[1])
    }

    func literal(_ e: ExprSyntax) -> String? {
        e.as(StringLiteralExprSyntax.self)?.segments.compactMap { $0.as(StringSegmentSyntax.self)?.content.text }.joined()
    }
}
