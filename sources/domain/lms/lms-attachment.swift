import Foundation

// 과제 소개에 붙은 파일. `path`는 LMS 기준 경로(`/pluginfile.php/…/mod_assign/introattachment/0/<이름>`)이고,
// `name`은 LMS에 올라온 원래 이름이다.
public struct LMSAttachment: Codable, Hashable, Sendable {
    public var name: String
    public var path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    public var url: URL { LMS.url(path) }

    // 첨부가 하나면 그 이름을, 여럿이면 첫 이름과 나머지 수를 보인다.
    public static func summary(_ attachments: [LMSAttachment]) -> (first: String, more: Int)? {
        attachments.first.map { ($0.name, attachments.count - 1) }
    }
}
