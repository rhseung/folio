import FolioActions
import FolioDomain
import FolioStorage
import Foundation

final class Probe {
    let builder: SchemaBuilder
    let caseIndex: Int
    var properties: [String: JSONValue] = [:]
    var nested: [String: Probe] = [:]
    var required: [String] = []
    var single: JSONValue?
    var caseCount = 0

    init(builder: SchemaBuilder, caseIndex: Int) {
        self.builder = builder
        self.caseIndex = caseIndex
    }

    var shape: JSONValue {
        if let single { return single }
        let all = properties.merging(nested.mapValues(\.shape)) { a, _ in a }
        return .object(["type": "object", "properties": .object(all), "required": .array(required.map(JSONValue.string))])
    }

    func field(_ key: CodingKey, _ schema: JSONValue, required: Bool) {
        properties[key.stringValue] = schema
        if required, !self.required.contains(key.stringValue) { self.required.append(key.stringValue) }
    }
}
