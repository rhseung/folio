import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Action("exam rm", "시험 기록 지우기", effect: .removes, confirm: "...", done: "...")` on a struct of fields and a
/// `run`: writes its init, coding, `spec` and `Action` conformance, so the declaration is all an action needs.
public struct ActionMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol,
                                 conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard !protocols.isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): FolioActions.Action {}")]
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
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

        let keys = fields.map(\.name).joined(separator: ", ")
        let params = fields.map { f in "\(f.name): \(f.type)" + (f.parameterDefault.map { " = \($0)" } ?? "") }.joined(separator: ", ")
        let assigns = fields.map { "self.\($0.name) = \($0.name)" }.joined(separator: "\n")
        let decodes = fields.map { "self.\($0.name) = \($0.decode)" }.joined(separator: "\n")
        let encodes = fields.map(\.encode).joined(separator: "\n")
        let specs = fields.map(\.spec).joined(separator: ",\n")
        return [
            fields.isEmpty ? "public enum CodingKeys: String, CodingKey { case _none }" : "public enum CodingKeys: String, CodingKey { case \(raw: keys) }",
            "public init(\(raw: params)) {\n\(raw: assigns)\n}",
            "public init(from decoder: any Decoder) throws {\nlet c = try decoder.container(keyedBy: CodingKeys.self)\n\(raw: fields.isEmpty ? "_ = c" : decodes)\n}",
            "public func encode(to encoder: any Encoder) throws {\nvar c = encoder.container(keyedBy: CodingKeys.self)\n\(raw: fields.isEmpty ? "_ = c" : encodes)\n}",
            """
            public static let spec = FolioActions.ActionSpec(command: \(raw: args.command), summary: \(raw: args.summary), discussion: \(raw: args.discussion), \
            effect: .\(raw: args.effect), confirm: \(raw: args.confirm ?? "nil"), done: \(raw: args.done), examples: \(raw: args.examples), \
            phrases: \(raw: args.phrases), generated: \(raw: args.generated), fields: [\n\(raw: specs)\n])
            """,
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

struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// The attribute's arguments as Swift source, to pass through into `ActionSpec(...)`.
private struct Arguments {
    var command = "", summary = "", discussion = "\"\"", effect = "changes", confirm: String?, done = "", examples = "[]", phrases = "[]"
    var generated = "true"
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
            case "cli": generated = source == ".manual" ? "false" : "true"
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

/// One stored property of the action.
private struct Field {
    enum Role { case argument, option, off(String), new, hidden }

    var name: String
    var type: String
    var defaultValue: String?
    var role: Role
    var help: String
    // What the type says.
    var patch = false, optional = false, many = false
    var ref: String?
    var base: String

    init?(_ decl: DeclSyntax) throws {
        guard let v = decl.as(VariableDeclSyntax.self), !v.modifiers.contains(where: { $0.name.text == "static" }),
              let binding = v.bindings.first, binding.accessorBlock == nil,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
        // A constant with a value isn't an input.
        if v.bindingSpecifier.text == "let", binding.initializer != nil { return nil }
        self.name = name
        defaultValue = binding.initializer?.value.trimmedDescription
        if let t = binding.typeAnnotation?.type.trimmedDescription {
            type = t
        } else if let d = defaultValue, d == "true" || d == "false" {
            type = "Bool"
        } else {
            throw MacroError("\(name)의 형식을 적어 주세요")
        }

        var role = Role.option
        for attr in v.attributes.compactMap({ $0.as(AttributeSyntax.self) }) {
            switch attr.attributeName.trimmedDescription {
            case "Arg": role = .argument
            case "New": role = .new
            case "Hidden": role = .hidden
            case "Off":
                let given = attr.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.as(StringLiteralExprSyntax.self)?
                    .segments.compactMap { $0.as(StringSegmentSyntax.self)?.content.text }.joined()
                role = .off(given ?? "off")
            default: break
            }
        }
        self.role = role
        help = v.leadingTrivia.compactMap { piece -> String? in
            if case .docLineComment(let text) = piece { return text.dropFirst(3).trimmingCharacters(in: .whitespaces) }
            return nil
        }.joined(separator: " ")

        var inner = type
        if inner.hasPrefix("Patch<"), inner.hasSuffix(">") { patch = true; inner = String(inner.dropFirst(6).dropLast()) }
        if inner.hasSuffix("?") { optional = true; inner = String(inner.dropLast()) }
        if inner.hasPrefix("["), inner.hasSuffix("]") { many = true; inner = String(inner.dropFirst().dropLast()) }
        if inner.hasSuffix(".ID") {
            ref = String(inner.dropLast(3).split(separator: ".").last!)
            base = "UUID"
        } else if inner.hasSuffix(".Path") {
            // A file named by its course-relative path: `Note.Path` is the kind "NotePath".
            ref = String(inner.dropLast(5).split(separator: ".").last!) + "Path"
            base = "String"
        } else {
            base = inner
        }
        if base == "UUID", ref == nil, !isHidden {
            throw MacroError("\(name): 맨 UUID 대신 가리키는 종류의 ID(예: Exam.ID)를 씁니다")
        }
        if case .new = role, ref == nil { throw MacroError("@New \(name)은(는) 만드는 항목의 ID(예: Exam.ID)여야 합니다") }
        if case .off = role, type != "Bool" { throw MacroError("@Off \(name)은(는) Bool이어야 합니다") }
    }

    var isHidden: Bool { if case .hidden = role { true } else { false } }
    var isNew: Bool { if case .new = role { true } else { false } }

    var parameterDefault: String? {
        if isNew { return defaultValue ?? "UUID()" }
        if patch { return defaultValue ?? ".keep" }
        if let defaultValue { return defaultValue }
        return optional && !patch ? "nil" : nil
    }

    var decode: String {
        if patch { return "try .decode(c, .\(name))" }
        let value = optional ? String(type.dropLast()) : type
        if let d = isNew ? (defaultValue ?? "UUID()") : defaultValue { return "try c.decodeIfPresent(\(value).self, forKey: .\(name)) ?? \(d)" }
        if optional { return "try c.decodeIfPresent(\(value).self, forKey: .\(name))" }
        return "try c.decode(\(type).self, forKey: .\(name))"
    }

    var encode: String {
        if patch { return "try \(name).encode(&c, .\(name))" }
        return optional ? "try c.encodeIfPresent(\(name), forKey: .\(name))" : "try c.encode(\(name), forKey: .\(name))"
    }

    var spec: String {
        let role = switch self.role {
        case .argument: ".argument"
        case .option: ".option"
        case .off(let flag): ".off(\(quoted(flag)))"
        case .new: ".new"
        case .hidden: ".hidden"
        }
        return "FolioActions.FieldSpec(name: \(quoted(name)), help: \(quoted(help)), role: \(role), type: \(quoted(base)), ref: \(ref.map(quoted) ?? "nil"), "
            + "optional: \(optional), many: \(many), patch: \(patch), defaultValue: \(defaultValue.map(quoted) ?? "nil"))"
    }

    func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
