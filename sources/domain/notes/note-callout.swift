import Foundation

// `settings.json`의 `callouts`에 사용자가 더하거나 고친 콜아웃 종류다. 기본 종류와 성질의 표는 FolioMarkdown의
// `CalloutKind`에 있고, 앱과 CLI가 이 값을 그 표에 더한다. FolioDomain은 FolioMarkdown을 보지 못하므로 `tone`은 그
// 표의 이름(`definition`, `theorem`, `example`, `warning`, `danger`, `neutral`)을 글자로 둔다.
public struct NoteCallout: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var tone: String
    public var numbered: Bool
    public var provable: Bool

    public init(name: String, tone: String, numbered: Bool = false, provable: Bool = false) {
        self.name = name
        self.tone = tone
        self.numbered = numbered
        self.provable = provable
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        tone = try c.value(.tone, or: "neutral")
        numbered = try c.value(.numbered, or: false)
        provable = try c.value(.provable, or: false)
    }
}
