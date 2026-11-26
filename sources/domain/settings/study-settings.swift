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
    // 단원 페이지가 오늘부터 펼쳐 보이는 계획의 날 수다. 그 밖의 날은 "더 보기"로 접는다.
    public var planShownDays: Int
    // 새 문제지 PDF가 들어오면 Claude가 저절로 문제를 뽑는다.
    public var autoExtract: Bool
    // 문제집 PDF의 표지에 쓰는 이름이다. 비어 있으면 표지에서 뺀다.
    public var coverName: String

    public init(
        readyPercent: Int = SettingItem.studyReadyPercent.int, minProblems: Int = SettingItem.studyMinProblems.int,
        finalDays: Int = SettingItem.studyFinalDays.int, mockMinutes: Int = SettingItem.studyMockMinutes.int,
        planDayItems: Int = SettingItem.studyPlanDayItems.int, planShownDays: Int = SettingItem.studyPlanShownDays.int,
        autoExtract: Bool = SettingItem.studyAutoExtract.bool,
        coverName: String = SettingItem.studyCoverName.text
    ) {
        self.readyPercent = readyPercent
        self.minProblems = minProblems
        self.finalDays = finalDays
        self.mockMinutes = mockMinutes
        self.planDayItems = planDayItems
        self.planShownDays = planShownDays
        self.autoExtract = autoExtract
        self.coverName = coverName
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StudySettings()
        readyPercent = try c.value(.readyPercent, or: d.readyPercent)
        minProblems = try c.value(.minProblems, or: d.minProblems)
        finalDays = try c.value(.finalDays, or: d.finalDays)
        mockMinutes = try c.value(.mockMinutes, or: d.mockMinutes)
        planDayItems = try c.value(.planDayItems, or: d.planDayItems)
        planShownDays = try c.value(.planShownDays, or: d.planShownDays)
        autoExtract = try c.value(.autoExtract, or: d.autoExtract)
        coverName = try c.value(.coverName, or: d.coverName)
    }

    public var readyScore: Double { Double(readyPercent) / 100 }
}
