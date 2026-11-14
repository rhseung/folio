import Foundation
import Testing

@testable import FolioDomain

struct SettingItemTests {
    // 기본 설정의 모든 값이 선언된 항목에 들어야 한다. 새 설정을 더하고 선언하지 않으면 여기서 실패한다.
    @Test func everyStoredKeyIsDeclared() throws {
        var full = Settings()
        full.review.dailyLimit = 10
        full.mathSnippets = []
        full.asciiMathSnippets = []
        full.callouts = []
        full.classStart.preset = "in-class"
        func leaves(_ node: JSONValue, _ path: String) -> [String] {
            if SettingItem.all.contains(where: { $0.key == path }) { return [] }
            guard case .object(let o) = node else { return [path] }
            return o.flatMap { key, child in leaves(child, path.isEmpty ? key : "\(path).\(key)") }
        }
        #expect(leaves(try json(full), "").isEmpty)
    }

    @Test func everyDeclaredKeyIsStored() throws {
        var full = Settings()
        full.review.dailyLimit = 10
        full.mathSnippets = []
        full.asciiMathSnippets = []
        full.callouts = []
        full.classStart.preset = "in-class"
        let root = try json(full)
        for item in SettingItem.all {
            let value = item.key.split(separator: ".").reduce(Optional(root)) { node, key in node?[String(key)] }
            #expect(value != nil, "\(item.key)")
        }
        #expect(Set(SettingItem.all.map(\.key)).count == SettingItem.all.count)
    }

    // 선언이 기본값의 단일 출처다. `Settings()`가 다른 값을 쓰면 화면과 `settings show`가 다른 기본값을 말한다.
    @Test func defaultsAreTheDeclarations() throws {
        let root = try json(Settings())
        for item in SettingItem.all {
            #expect((item.value(in: root) ?? .null) == item.fallback, "\(item.key)")
        }
    }

    @Test func calloutKindsReadWithTheirDefaults() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"callouts": [{"name": "claim", "numbered": true}]}"#.utf8))
        #expect(settings.callouts == [NoteCallout(name: "claim", tone: "neutral", numbered: true)])
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).callouts == nil)
    }

    @Test func defaultsPassTheirOwnChecks() throws {
        #expect(SettingItem.problems(in: try json(Settings())).isEmpty)
    }

    @Test func valuesOutsideTheScreenRangesAreRefused() {
        #expect(SettingItem.reviewSettleAfter.problem(.number(5)) == nil)
        #expect(SettingItem.reviewSettleAfter.problem(.number(6)) != nil)
        #expect(SettingItem.reviewSettleAfter.problem(.number(2.5)) != nil)
        #expect(SettingItem.reviewIntervals.problem(.array([])) != nil)
        #expect(SettingItem.reviewIntervals.problem(.array([.number(1), .number(400)])) != nil)
        #expect(SettingItem.reviewDailyLimit.problem(.null) == nil)
        #expect(SettingItem.classMinutes.problem(.null) != nil)
        #expect(SettingItem.newNoteMath.problem(.string("latex")) == nil)
        #expect(SettingItem.newNoteMath.problem(.string("mathml")) != nil)
        #expect(SettingItem.backupDailyDays.problem(.number(0)) != nil)
        #expect(SettingItem.backupDailyDays.problem(.number(9000)) == nil)
    }

    @Test func timeRangesAreMinutes() {
        #expect(SettingItem.dayBoundary.range == 0...480)
        #expect(SettingItem.dayBoundary.hours == 0...8)
        #expect(SettingItem.dayBoundary.problem(.number(8 * 60)) == nil)
        #expect(SettingItem.dayBoundary.problem(.number(8 * 60 + 5)) != nil)
        #expect(SettingItem.examMorningMinute.hours == 0...23)
    }

    @Test func fieldsUnderACustomItemAndParentObjectsAreKnown() {
        #expect(SettingItem.unknown("review") == nil)
        #expect(SettingItem.unknown("review.intervals") == nil)
        #expect(SettingItem.unknown("classStart.courseOff.abc") == nil)
        #expect(SettingItem.unknown("review.intervalz") != nil)
        #expect(SettingItem.unknown("review.intervals.0") != nil)
    }

    @Test func checksOnlyTheChangedField() throws {
        var root = try json(Settings())
        root["classMinutes"] = .number(1)
        #expect(SettingItem.problems(in: root, under: "review").isEmpty)
        #expect(SettingItem.problems(in: root, under: "classMinutes").count == 1)
        #expect(SettingItem.problems(in: root).count == 1)
    }
}

private func json(_ settings: Settings) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(settings))
}
