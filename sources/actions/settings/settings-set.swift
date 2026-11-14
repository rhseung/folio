import FolioDomain
import FolioStorage
import Foundation

@Action(
    "settings set", "설정 하나를 바꾸거나 settings.json 전체를 파일 내용으로 바꾸기",
    discussion: """
        필드는 settings.json의 이름을 점으로 이어 쓴다(`folio settings show --json`). 값은 JSON으로 읽고, JSON이 아니면 글자로 읽는다.
        있는 필드만 바꿀 수 있다. 모양이 맞지 않는 값은 쓰지 않는다(종료 코드 2).
        """,
    done: "설정을 바꿨습니다",
    examples: [
        "folio settings set dayBoundaryMinutes 300", #"folio settings set review.intervals "[1, 3, 7, 14, 30]" --dry-run"#,
        "folio settings set --file settings.json --dry-run",
    ],
    phrases: ["설정 변경", "하루 경계", "복습 간격", "알림 시간"])
public struct SettingsSet {
    /// 필드. 예: review.intervals
    @Arg var field: String?
    /// 새 값
    @Arg var value: JSONValue?
    /// settings.json 형식의 파일. 필드 대신 설정 전체를 바꾼다
    @CLIName("file") @FromFile("path") var settings: Settings?

    public func run(_ ctx: ActionContext) throws {
        let new: Settings
        if let settings {
            guard field == nil, value == nil else { throw ActionError.input(String(localized: .errorSettingsFieldOrFile)) }
            new = settings
        } else {
            guard let field, let value else { throw ActionError.input(String(localized: .errorSettingsNeedsFieldAndValue)) }
            var root = try JSONValue(ctx.settings())
            try root.set(field.split(separator: ".").map(String.init), to: value, path: field)
            do {
                new = try JSONDecoder.folio.decode(Settings.self, from: JSONEncoder.folio.encode(root))
            } catch let e as DecodingError {
                throw ActionError.input(String(localized: .errorSettingsBadValue(field, e.summary)))
            }
        }
        try ctx.editSettings { $0 = new }
    }
}
