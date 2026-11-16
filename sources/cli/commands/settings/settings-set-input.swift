import FolioActions
import FolioCore
import FolioDomain
import Foundation

// 에이전트가 필드 이름과 값의 모양을 추측하지 않도록, 선언된 항목마다 이름, 모양, 기본값을 적는다.
extension SettingsSet: InputRefining {
    static func refine(_ input: JSONValue) -> JSONValue {
        var input = input
        let lines = SettingItem.all.map { item in
            "\(item.key): \(String(localized: item.name)). \(item.shapeText). "
                + String(localized: .settingsShowDefault(item.text(of: item.fallback)))
        }
        input["properties"]?["field"] = [
            "type": "string", "enum": .array(SettingItem.all.map { .string($0.key) }),
            "description": .string(lines.joined(separator: "\n")),
        ]
        return input
    }
}
