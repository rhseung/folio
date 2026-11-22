import FolioDomain
import Foundation

// 회차의 단원과 시험 범위는 저장하지 않고 계산하므로, 항목만 쓰면 `--json`에서 연결이 사라진다. 계산한 연결을 저장하던
// 때의 키 이름으로 항목 옆에 함께 쓴다. 그래야 JSON을 읽는 도구(MCP, 스크립트)가 그대로 돈다.
public struct QueryLinks<Item: Encodable & Sendable>: Encodable, Sendable {
    public var item: Item
    public var links: [(key: String, ids: [UUID])]

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public func encode(to encoder: Encoder) throws {
        try item.encode(to: encoder)
        var c = encoder.container(keyedBy: Key.self)
        for link in links { try c.encode(link.ids, forKey: Key(stringValue: link.key)) }
    }
}

extension QueryLinks where Item == Session {
    public init(_ session: Session, in file: CourseFile) {
        self.init(item: session, links: [("unitIds", file.unitIds(of: session))])  // strings: data, 예전 JSON 키
    }
}

extension QueryLinks where Item == FolioDomain.Unit {
    public init(_ unit: FolioDomain.Unit, in file: CourseFile) {
        self.init(
            item: unit,
            links: [
                ("sessionIds", file.sessions(of: unit.id).map(\.id)),  // strings: data, 예전 JSON 키
                ("examIds", file.exams(scoping: unit.id).map(\.id)),  // strings: data, 예전 JSON 키
            ])
    }
}

extension QueryLinks where Item == Exam {
    public init(_ exam: Exam, in file: CourseFile) {
        self.init(item: exam, links: [("scopeUnitIds", file.scope(of: exam))])  // strings: data, 예전 JSON 키
    }
}
