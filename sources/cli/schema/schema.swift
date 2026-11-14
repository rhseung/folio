import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Array: SniffArray where Element: Decodable { static var element: any Decodable.Type { Element.self } }
extension Set: SniffArray where Element: Decodable { static var element: any Decodable.Type { Element.self } }
extension Dictionary: SniffDictionary where Key == String, Value: Decodable { static var value: any Decodable.Type { Value.self } }
extension Optional: SniffOptional where Wrapped: Decodable { static var wrapped: any Decodable.Type { Wrapped.self } }

extension String: SchemaHint { static var schema: JSONValue { ["type": "string"] }; static var example: Any { "" } }
extension Bool: SchemaHint { static var schema: JSONValue { ["type": "boolean"] }; static var example: Any { false } }
extension Int: SchemaHint { static var schema: JSONValue { ["type": "integer"] }; static var example: Any { 0 } }
extension Int64: SchemaHint { static var schema: JSONValue { ["type": "integer"] }; static var example: Any { Int64(0) } }
extension Double: SchemaHint { static var schema: JSONValue { ["type": "number"] }; static var example: Any { 0.0 } }
extension UUID: SchemaHint { static var schema: JSONValue { ["type": "string", "format": "uuid"] }; static var example: Any { UUID() } }
extension Date: SchemaHint {
    static var schema: JSONValue { ["type": "string", "format": "date-time"] }; static var example: Any { Date() }
}
extension Data: SchemaHint {
    static var schema: JSONValue { ["type": "string", "contentEncoding": "base64"] }; static var example: Any { Data() }
}
extension URL: SchemaHint {
    static var schema: JSONValue { ["type": "string", "format": "uri"] }; static var example: Any { URL(filePath: "/") }
}
extension JSONValue: SchemaHint { static var schema: JSONValue { [:] }; static var example: Any { JSONValue.null } }
extension LocalDate: SchemaHint {
    static var schema: JSONValue { ["type": "string", "format": "date"] }
    static var example: Any { LocalDate(year: 2026, month: 1, day: 1)! }
}
extension Aggregation: SchemaHint {
    static var schema: JSONValue { ["type": "string", "description": "sum, mean, single, dropLowest:<n>, bestOf:<n>"] }
    static var example: Any { Aggregation.sum }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(elements) { a, _ in a }) }
}

func declaredInput(_ spec: ActionSpec, _ sniffed: JSONValue) -> JSONValue {
    guard case .object(var o) = sniffed, case .object(var props)? = o["properties"], case .array(let required)? = o["required"] else {
        return sniffed
    }
    for f in spec.fields {
        guard case .object(var p)? = props[f.name] else { continue }
        if let kind = f.ref {
            let one: JSONValue = ["type": "string", "x-folio-ref": .string(kind)]
            p = f.many ? ["type": "array", "items": one] : ["type": "string", "x-folio-ref": .string(kind)]
        }
        // JSON 입력은 명령의 `2026-11-20 23:59`와 달리 오프셋이 붙은 RFC 3339만 받는데, 이 안내가 없을 때 에이전트가 잘못
        // 추측했다.
        let dateHint = p["format"] == "date-time" ? "시간대를 붙인 ISO 8601. 예: 2026-11-20T23:59:00+09:00" : ""
        let help = [f.help, f.patch && f.optional ? "null이면 지운다" : "", dateHint].filter { !$0.isEmpty }.joined(separator: ". ")
        if !help.isEmpty { p["description"] = .string(help) }
        props[f.name] = .object(p)
    }
    let optional = Set(spec.fields.filter { $0.patch || $0.role == .new }.map(\.name))
    o["properties"] = .object(props)
    o["required"] = .array(required.filter { if case .string(let k) = $0 { !optional.contains(k) } else { true } })
    return .object(o)
}

let actionRefNote =
    "항목을 가리키는 필드(course, semester, session, exam, unit, material, component, assignment, set, note)는 UUID와 이름(EC4207, 11-03, Quiz1)을 모두 받는다. 새 항목의 id는 빼면 만들어진다. x-folio-ref가 있는 필드는 그 종류의 항목을 가리킨다. NotePath는 노트를 과목 폴더 기준 경로로 가리키고, 노트 이름도 받는다."

func actionSchemas() -> JSONValue {
    let builder = SchemaBuilder()
    let refNote = actionRefNote + " asks가 true인 액션은 --yes 없이 터미널이 아니면 종료 코드 5로 멈춘다."
    let actions = Actions.all.map { type -> JSONValue in
        let spec = type.spec
        guard !spec.done.isEmpty else {
            return ["command": .string(type.command), "type": .string(String(describing: type)), "input": builder.inline(type)]
        }
        return [
            "command": .string(type.command),
            "type": .string(String(describing: type)),
            "summary": .string(spec.summary),
            "effect": .string(spec.effect.rawValue),
            "asks": .bool(spec.effect == .removes || spec.effect == .moves),
            "input": declaredInput(spec, builder.inline(type)),
        ]
    }
    return [
        "description": .string(refNote),
        "run": "folio run <command> --input '<JSON>'",
        "result": [
            "type": "object",
            "properties": [
                "action": ["type": "string"], "dryRun": ["type": "boolean"], "made": ["type": "string", "format": "uuid"],
                "changes": ["type": "array"],
            ],
        ],
        "actions": .array(actions),
        "$defs": .object(builder.defs),
    ]
}
extension AssignmentRepeat: SchemaHint {
    static var schema: JSONValue {
        let rule: JSONValue = [
            "type": "object", "required": .array(["every", "unit"]),
            "properties": [
                "every": ["type": "integer", "minimum": .number(1)],
                "unit": ["type": "string", "enum": .array(Unit.allCases.map { .string($0.rawValue) })],
                "weekdays": [
                    "type": "array", "items": ["type": "integer", "minimum": .number(1), "maximum": .number(7)],
                    "description": "ISO weekdays, 1 = Monday; week only",
                ],
            ],
        ]
        let words: JSONValue = [
            "type": "string",
            "description": "daily, weekly, biweekly, monthly, 3d, 2w, 1m, weekly:mon,wed, 매일, 격일, 3일마다, 격주, 매월, 매주 월수, 월,수마다, 평일마다",
        ]
        return ["oneOf": .array([rule, words])]
    }
    static var example: Any { AssignmentRepeat.weekly }
}
