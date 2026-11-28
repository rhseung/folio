import FolioCore
import FolioDomain
import Foundation
import Testing

@testable import FolioStorage

// v1의 카드에는 형식이 없다. v2는 그 카드를 앞뒤 카드로 읽는다.
struct CardKindMigrationTests {
    let unit = UUID(), card = UUID()

    var v1: JSONValue {
        .object([
            "schemaVersion": .number(1), "unitId": .string(unit.uuidString), "futureSection": .object(["kept": .bool(true)]),
            "cards": .array([
                .object([
                    "id": .string(card.uuidString), "unitId": .string(unit.uuidString), "front": .string("매칭"),
                    "back": .string("공통 끝점이 없는 변의 집합"), "hint": .string("모르는 필드"),
                ])
            ]),
        ])
    }

    @Test func oldCardsBecomeFlipCards() throws {
        var raw = v1
        try CardFile.markFlipCards(&raw)
        guard case .array(let cards)? = raw["cards"] else {
            Issue.record("no cards")
            return
        }
        #expect(cards[0]["kind"] == .string(CardKind.flip.rawValue) && cards[0]["hint"] == .string("모르는 필드"))

        var twice = raw
        try CardFile.markFlipCards(&twice)
        #expect(twice == raw)
    }

    @Test func aVersionOneFileOpensAndKeepsUnknownFieldsWhenSaved() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "\(unit.uuidString).json")
        try JSONFormat.encoder.encode(v1).write(to: url)

        var doc = try StoredDocument<CardFile>.read(from: url)
        #expect(doc.model.cards.map(\.kind) == [.flip] && doc.model.cards[0].answer == nil)
        var asked = StudyCard(
            device: UUID(), at: Date(timeIntervalSince1970: 1_790_000_000), unitId: unit, kind: .trueFalse,
            front: "모든 정규 이분 그래프에는 완전 매칭이 있다.", back: "홀의 조건을 만족한다.",
            answer: true)
        asked.noteId = UUID()
        asked.noteSection = "정리와 증명"
        doc.model.cards.append(asked)
        try doc.write(to: url)

        let saved = try JSONFormat.decoder.decode(JSONValue.self, from: Data(contentsOf: url))
        guard case .array(let cards)? = saved["cards"] else {
            Issue.record("no cards")
            return
        }
        #expect(saved["schemaVersion"] == .number(2) && saved["futureSection"] != nil)
        #expect(cards[0]["hint"] == .string("모르는 필드") && cards[0]["kind"] == .string("flip"))
        #expect(cards[1]["kind"] == .string("true_false") && cards[1]["answer"] == .bool(true))
        #expect(try StoredDocument<CardFile>.read(from: url).model.cards.last == asked)
    }
}
