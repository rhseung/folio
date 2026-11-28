import FolioCore
import Foundation

// 예전 계획의 `finalDays`와 `planDayItems`는 모르는 키로 읽어 보존하고 더 쓰지 않는다.
public struct StudySettings: Codable, Sendable, Equatable {
    // 준비됨이 되는 준비 점수다. 정수 항목만 화면에서 고르므로 백분율로 둔다.
    public var readyPercent: Int
    public var minProblems: Int
    // 시험 정보에 시간이 없을 때 모의고사의 제한 시간이다.
    public var mockMinutes: Int
    // 계획 블록이 내일부터 펼쳐 보이는 날 수다. 그 뒤의 날은 "더 보기"로 접는다.
    public var planShownDays: Int
    // 새 문제지 PDF가 들어오면 Claude가 저절로 문제를 뽑는다.
    public var autoExtract: Bool
    // 문제집 PDF의 표지에 쓰는 이름이다. 비어 있으면 표지에서 뺀다.
    public var coverName: String

    public init(
        readyPercent: Int = SettingItem.studyReadyPercent.int, minProblems: Int = SettingItem.studyMinProblems.int,
        mockMinutes: Int = SettingItem.studyMockMinutes.int, planShownDays: Int = SettingItem.studyPlanShownDays.int,
        autoExtract: Bool = SettingItem.studyAutoExtract.bool, coverName: String = SettingItem.studyCoverName.text
    ) {
        self.readyPercent = readyPercent
        self.minProblems = minProblems
        self.mockMinutes = mockMinutes
        self.planShownDays = planShownDays
        self.autoExtract = autoExtract
        self.coverName = coverName
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StudySettings()
        readyPercent = try c.value(.readyPercent, or: d.readyPercent)
        minProblems = try c.value(.minProblems, or: d.minProblems)
        mockMinutes = try c.value(.mockMinutes, or: d.mockMinutes)
        planShownDays = try c.value(.planShownDays, or: d.planShownDays)
        autoExtract = try c.value(.autoExtract, or: d.autoExtract)
        coverName = try c.value(.coverName, or: d.coverName)
    }

    public var readyScore: Double { Double(readyPercent) / 100 }
}
