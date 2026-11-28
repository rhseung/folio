import FolioCore
import FolioDomain
import Foundation
import Testing

@testable import FolioStorage

struct SettingsMigrationTests {
    func write(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func raw(_ url: URL) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)) }

    @Test func v1NotificationFieldsMoveIntoTheirKinds() throws {
        let url = try write(
            #"""
            {"schemaVersion":1,"dayBoundaryMinutes":300,"kept":1,"notifications":{"assignmentDue":false,"assignmentLeadHours":[48,6],
            "examDayBefore":true,"examDayBeforeMinute":1230,"examMorning":false,"examMorningMinute":420,"dailyReview":true,
            "dailyReviewMinute":1320,"attendance":false,"later":"kept"}}
            """#)
        let doc = try StoredDocument<Settings>.read(from: url)
        #expect(doc.fileVersion == 1)
        let n = doc.model.notifications
        #expect(n[.assignmentDue] == .init(on: false, leadHours: [48, 6]))
        #expect(n[.examDayBefore] == .init(on: true, minute: 1230))
        #expect(n[.examMorning] == .init(on: false, minute: 420))
        #expect(n[.attendance] == .init(on: false))
        #expect(doc.model.dayBoundaryMinutes == 300)

        try doc.write(to: url)
        let saved = try raw(url)
        #expect(saved["schemaVersion"] == .number(2))
        #expect(saved["kept"] == .number(1))
        #expect(saved["notifications"]?["later"] == .string("kept"))
        // 매일 복습 알림은 없어졌지만, 예전 판이 읽도록 파일에는 남긴다.
        #expect(saved["notifications"]?["dailyReview"] == .object(["on": .bool(true), "minute": .number(1320)]))
        #expect(saved["notifications"]?["examMorning"] == .object(["on": .bool(false), "minute": .number(420)]))
        #expect(saved["notifications"]?["assignmentLeadHours"] == nil && saved["notifications"]?["examMorningMinute"] == nil)
        #expect(try StoredDocument<Settings>.read(from: url).model == doc.model)
    }

    @Test func missingFieldsKeepTheirDefaults() throws {
        let url = try write(#"{"schemaVersion":1,"notifications":{"examMorningMinute":420}}"#)
        let n = try StoredDocument<Settings>.read(from: url).model.notifications
        #expect(n[.examMorning] == .init(on: true, minute: 420))
        #expect(n[.examDayBefore] == NotificationSettings.Kind.examDayBefore.defaultRule)
        var expected = NotificationSettings()
        expected[.examMorning].minute = 420
        #expect(n == expected)
        let none = try write(#"{"schemaVersion":1}"#)
        #expect(try StoredDocument<Settings>.read(from: none).model.notifications == NotificationSettings())
    }

    // 계획이 더 쓰지 않는 공부 설정은 읽지 않지만, 예전 판이 읽도록 파일에는 남긴다.
    @Test func retiredPlanSettingsStayInTheFile() throws {
        let url = try write(#"{"schemaVersion":2,"study":{"finalDays":2,"planDayItems":4,"mockMinutes":60}}"#)
        var doc = try StoredDocument<Settings>.read(from: url)
        #expect(doc.model.study.mockMinutes == 60)
        doc.model.study.planShownDays = 5
        try doc.write(to: url)
        let saved = try raw(url)
        #expect(saved["study"]?["finalDays"] == .number(2) && saved["study"]?["planDayItems"] == .number(4))
        #expect(saved["study"]?["planShownDays"] == .number(5) && saved["study"]?["mockMinutes"] == .number(60))
    }

    // 종류 객체 안의 모르는 필드도 저장할 때 남는다.
    @Test func unknownFieldsInsideAKindAreKept() throws {
        let url = try write(#"{"schemaVersion":2,"notifications":{"examMorning":{"on":true,"minute":480,"sound":"bell"}}}"#)
        var doc = try StoredDocument<Settings>.read(from: url)
        doc.model.notifications[.examMorning].minute = 450
        try doc.write(to: url)
        let saved = try raw(url)
        #expect(saved["notifications"]?["examMorning"] == .object(["on": .bool(true), "minute": .number(450), "sound": .string("bell")]))
    }
}
