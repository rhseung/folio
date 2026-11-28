import FolioCore
import Foundation
import Testing

@testable import FolioDomain

struct SettingItemTests {
    // 기본 설정의 모든 값이 선언된 항목에 들어야 한다. 새 설정을 더하고 선언하지 않으면 여기서 실패한다.
    @Test func everyStoredKeyIsDeclared() throws {
        var full = Settings()
        full.mathSnippets = []
        full.asciiMathSnippets = []
        full.callouts = []
        full.assignmentKinds = []
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
        full.mathSnippets = []
        full.asciiMathSnippets = []
        full.callouts = []
        full.assignmentKinds = []
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
        #expect(SettingItem.studyReadyPercent.problem(.number(80)) == nil)
        #expect(SettingItem.studyReadyPercent.problem(.number(40)) != nil)
        #expect(SettingItem.studyPlanShownDays.problem(.number(15)) != nil)
        #expect(SettingItem.studyMinProblems.problem(.number(2.5)) != nil)
        #expect(SettingItem.classMinutes.problem(.null) != nil)
        #expect(SettingItem.newNoteMath.problem(.string("latex")) == nil)
        #expect(SettingItem.newNoteMath.problem(.string("mathml")) != nil)
        #expect(SettingItem.backupDailyDays.problem(.number(0)) != nil)
        #expect(SettingItem.backupDailyDays.problem(.number(9000)) == nil)
    }

    @Test func timeRangesCoverTheLastHoursMinutes() {
        #expect(SettingItem.dayBoundary.range == 0...8 * 60 + 59)
        #expect(SettingItem.dayBoundary.hours == 0...8)
        #expect(SettingItem.dayBoundary.problem(.number(8 * 60 + 30)) == nil)
        #expect(SettingItem.dayBoundary.problem(.number(8 * 60 + 59)) == nil)
        #expect(SettingItem.dayBoundary.problem(.number(9 * 60)) != nil)
        #expect(SettingItem.examMorningMinute.hours == 0...23)
        #expect(SettingItem.examMorningMinute.range == 0...24 * 60 - 1)
    }

    // 시간 선택은 범위의 시마다 5분 단위 분을 모두 고르게 한다. 고를 수 있는 값은 모두 저장 검사를 통과해야 한다.
    @Test func everyPickableTimeIsAccepted() {
        for item in SettingItem.all {
            guard case .time = item.shape else { continue }
            for hour in item.hours {
                for minute in stride(from: 0, to: 60, by: 5) {
                    #expect(item.problem(.number(Double(hour * 60 + minute))) == nil, "\(item.key) \(hour):\(minute)")
                }
            }
        }
    }

    @Test func aBoundarySavedLateInTheLastHourStillReads() throws {
        let file = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"dayBoundaryMinutes": 530, "idleMinutes": 10}"#.utf8))
        #expect(SettingItem.problems(in: file).isEmpty)
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"dayBoundaryMinutes": 530}"#.utf8))
        #expect(settings.dayBoundaryMinutes == 530)
        #expect(settings.violations.isEmpty)
    }

    @Test func fieldsUnderACustomItemAndParentObjectsAreKnown() {
        #expect(SettingItem.unknown("study") == nil)
        #expect(SettingItem.unknown("study.readyPercent") == nil)
        #expect(SettingItem.unknown("classStart.courseOff.abc") == nil)
        #expect(SettingItem.unknown("study.readyPercentz") != nil)
        #expect(SettingItem.unknown("study.readyPercent.0") != nil)
    }

    @Test func checksOnlyTheChangedField() throws {
        var root = try json(Settings())
        root["classMinutes"] = .number(1)
        #expect(SettingItem.problems(in: root, under: "review").isEmpty)
        #expect(SettingItem.problems(in: root, under: "classMinutes").count == 1)
        #expect(SettingItem.problems(in: root).count == 1)
    }

    // 설정 화면은 묶음의 항목을 모양만 보고 행으로 그린다. 행이 그릴 수 없는 모양이 묶음에 들어가면 화면에서 빠진다.
    @Test func groupedItemsHaveARowShape() {
        for item in SettingItem.all where item.group != nil {
            #expect(item.shape != .custom, "\(item.key)")
            if case .choice(let values) = item.shape {
                #expect(item.options.map(\.value) == values, "\(item.key)")
            }
            if item.optional, case .number = item.shape {
                #expect(item.starting.map(item.range.contains) == true, "\(item.key)")
            }
        }
    }

    @Test func everyGroupHasRows() {
        for group in SettingGroup.allCases {
            #expect(!group.rows.isEmpty, "\(group)")
        }
    }

    // 스위치가 되는 토글은 같은 묶음에 있어야 그 묶음을 그릴 때 행으로 따로 그려지지 않는다.
    @Test func switchesAreTogglesInTheSameGroup() throws {
        for item in SettingItem.all {
            guard let key = item.switchedBy else { continue }
            let toggle = try #require(SettingItem.item(key), "\(item.key)")
            #expect(toggle.shape == .toggle, "\(item.key)")
            #expect(toggle.group == item.group, "\(item.key)")
        }
    }

    @Test func writingAValueKeepsTheOthers() throws {
        let start = Settings()
        let written = try #require(SettingItem.classMinutes.writing(.number(90), into: start))
        #expect(written.classMinutes == 90)
        #expect(written.dayBoundaryMinutes == start.dayBoundaryMinutes)
        let nested = try #require(SettingItem.examMinutes.writing(.number(150), into: written))
        #expect(nested.schedule.examMinutes == 150)
        #expect(nested.classMinutes == 90)
        #expect(SettingItem.studyReadyPercent.current(in: nested.json) == .number(80))
        #expect(SettingItem.classMinutes.current(in: .object([:])) == SettingItem.classMinutes.fallback)
    }
}

private func json(_ settings: Settings) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(settings))
}
