import FolioCore
import Foundation

public struct StudySettings: Codable, Sendable, Equatable {
    // 준비됨이 되는 준비 점수다. 정수 항목만 화면에서 고르므로 백분율로 둔다.
    public var readyPercent: Int
    public var minProblems: Int
    // 시험 직전에 섞어 풀기, 모의시험, 오답에 쓰는 날 수다.
    public var finalDays: Int
    // 시험 정보에 시간이 없을 때 모의시험의 제한 시간이다.
    public var mockMinutes: Int
    // 계획에서 하루에 두는 단원 항목 수다. 그날 몫의 단원이 더 많으면 이 수만큼의 묶음 항목으로 합친다.
    public var planDayItems: Int
    // 새 문제지 PDF가 들어오면 Claude가 저절로 문제를 뽑는다.
    public var autoExtract: Bool

    public init(
        readyPercent: Int = SettingItem.studyReadyPercent.int, minProblems: Int = SettingItem.studyMinProblems.int,
        finalDays: Int = SettingItem.studyFinalDays.int, mockMinutes: Int = SettingItem.studyMockMinutes.int,
        planDayItems: Int = SettingItem.studyPlanDayItems.int, autoExtract: Bool = SettingItem.studyAutoExtract.bool
    ) {
        self.readyPercent = readyPercent
        self.minProblems = minProblems
        self.finalDays = finalDays
        self.mockMinutes = mockMinutes
        self.planDayItems = planDayItems
        self.autoExtract = autoExtract
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StudySettings()
        readyPercent = try c.value(.readyPercent, or: d.readyPercent)
        minProblems = try c.value(.minProblems, or: d.minProblems)
        finalDays = try c.value(.finalDays, or: d.finalDays)
        mockMinutes = try c.value(.mockMinutes, or: d.mockMinutes)
        planDayItems = try c.value(.planDayItems, or: d.planDayItems)
        autoExtract = try c.value(.autoExtract, or: d.autoExtract)
    }

    public var readyScore: Double { Double(readyPercent) / 100 }
}
