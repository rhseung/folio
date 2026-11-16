import Foundation

public struct SchoolSettings: Codable, Sendable, Equatable {
    public var staffMailDomain = SettingItem.staffMailDomain.text
    public var studentMailDomain = SettingItem.studentMailDomain.text

    public init() {}

    public var staffMailPrompt: String { "name@" + staffMailDomain }
    public var studentMailPrompt: String { "name@" + studentMailDomain }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        staffMailDomain = try c.value(.staffMailDomain, or: d.staffMailDomain)
        studentMailDomain = try c.value(.studentMailDomain, or: d.studentMailDomain)
    }
}
