import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

struct Field {
    enum Role { case argument, option, off(String), new, hidden }

    var name: String
    var type: String
    var defaultValue: String?
    var role: Role
    var help: String
    var patch = false, optional = false, many = false
    var ref: String?
    var base: String
    var cliName: String?, file: String?, filePerItem = false, folder = false
    var parsed: String?, parsedForm: String?
    var wholeFile = false

    init?(_ decl: DeclSyntax) throws {
        guard let v = decl.as(VariableDeclSyntax.self), !v.modifiers.contains(where: { $0.name.text == "static" }),
            let binding = v.bindings.first, binding.accessorBlock == nil,
            let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
        else { return nil }
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
            let given = attr.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.as(StringLiteralExprSyntax.self)?
                .segments.compactMap { $0.as(StringSegmentSyntax.self)?.content.text }.joined()
            switch attr.attributeName.trimmedDescription {
            case "Arg": role = .argument
            case "New": role = .new
            case "Hidden": role = .hidden
            case "Off": role = .off(given ?? "off")
            case "CLIName": cliName = given
            case "FromFile":
                let args = attr.arguments?.as(LabeledExprListSyntax.self)
                file = args?.first(where: { $0.label == nil }) == nil ? "file" : given ?? "file"
                filePerItem = args?.contains { $0.label?.text == "perItem" && $0.expression.trimmedDescription == "true" } ?? false
            case "Folder": folder = true
            case "WholeFile": wholeFile = true
            case "Parsed":
                let texts =
                    attr.arguments?.as(LabeledExprListSyntax.self)?.map {
                        $0.expression.as(StringLiteralExprSyntax.self)?.segments.compactMap {
                            $0.as(StringSegmentSyntax.self)?.content.text
                        }.joined()
                    } ?? []
                guard texts.count == 2, let name = texts[0], let form = texts[1] else {
                    throw MacroError("@Parsed(\"<값 이름>\", \"<쓰는 꼴>\")")
                }
                (parsed, parsedForm) = (name, form)
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
            ref = inner.dropLast(3).split(separator: ".").last.map(String.init)
            base = "UUID"
        } else if inner.hasSuffix(".Path") {
            ref = inner.dropLast(5).split(separator: ".").last.map { $0 + "Path" }
            base = "String"
        } else {
            base = inner
        }
        if base == "UUID", ref == nil, !isHidden {
            throw MacroError("\(name): 맨 UUID 대신 가리키는 종류의 ID(예: Exam.ID)를 씁니다")
        }
        if case .new = role, ref == nil { throw MacroError("@New \(name)은(는) 만드는 항목의 ID(예: Exam.ID)여야 합니다") }
        if case .off = role, type != "Bool" { throw MacroError("@Off \(name)은(는) Bool이어야 합니다") }
        if file != nil || folder, ref != nil || patch { throw MacroError("@FromFile, @Folder \(name)은(는) 항목 ID나 Patch가 아닌 값이어야 합니다") }
        if folder, base != "String" || many { throw MacroError("@Folder \(name)은(는) String이어야 합니다") }
        if filePerItem, !many { throw MacroError("@FromFile(perItem:) \(name)은(는) 목록이어야 합니다") }
        if parsed != nil, ref != nil || file != nil || folder { throw MacroError("@Parsed \(name)은(는) 항목 ID나 파일이 아닌 값이어야 합니다") }
        if wholeFile, ref != nil || patch || many { throw MacroError("@WholeFile \(name)은(는) 문서 하나여야 합니다") }
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
        if let d = isNew ? (defaultValue ?? "UUID()") : defaultValue {
            return "try c.decodeIfPresent(\(value).self, forKey: .\(name)) ?? \(d)"
        }
        if optional { return "try c.decodeIfPresent(\(value).self, forKey: .\(name))" }
        return "try c.decode(\(type).self, forKey: .\(name))"
    }

    var encode: String {
        if patch { return "try \(name).encode(&c, .\(name))" }
        return optional ? "try c.encodeIfPresent(\(name), forKey: .\(name))" : "try c.encode(\(name), forKey: .\(name))"
    }

    var spec: String {
        let role =
            switch self.role {
            case .argument: ".argument"
            case .option: ".option"
            case .off(let flag): ".off(\(quoted(flag)))"
            case .new: ".new"
            case .hidden: ".hidden"
            }
        return
            "FolioActions.FieldSpec(name: \(quoted(name)), help: \(quoted(help)), role: \(role), type: \(quoted(base)), ref: \(ref.map { "FolioDomain.ItemKind.\(caseName($0))" } ?? "nil"), "
            + "optional: \(optional), many: \(many), patch: \(patch), defaultValue: \(defaultValue.map(quoted) ?? "nil"), "
            + "cliName: \(cliName.map(quoted) ?? "nil"), file: \(file.map(quoted) ?? "nil"), filePerItem: \(filePerItem), folder: \(folder), "
            + "parsed: \(parsed.map(quoted) ?? "nil"), parsedForm: \(parsedForm.map(quoted) ?? "nil"))"
    }

    // `ItemKind`의 경우 이름은 타입 이름의 첫 글자를 소문자로 바꾼 것이다. 표에 없는 종류는 생성한 코드가 컴파일되지 않는다.
    func caseName(_ type: String) -> String { type.prefix(1).lowercased() + type.dropFirst() }

    func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
