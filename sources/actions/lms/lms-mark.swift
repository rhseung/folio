import FolioDomain
import FolioStorage
import Foundation

@Action(
    "lms mark", "LMS 항목을 제안함에서 숨기기, --off면 다시 제안하기",
    done: "LMS 항목 {keys}을(를) 표시했습니다",
    examples: ["folio lms mark notice:23464 file:139109", "folio lms mark notice:23464 --off"],
    phrases: ["LMS 제안 무시", "LMS 공지 숨기기"])
public struct LMSMark {
    /// 항목. assignment:139941, file:139109, notice:23464 꼴
    @Arg var keys: [String]
    /// 다시 제안하기
    @Off("off") var handled = true

    public func run(_ ctx: ActionContext) throws {
        guard !keys.isEmpty else { throw ActionError.input(String(localized: .errorLmsNoKeys)) }
        let parsed = try keys.map { text in
            guard let key = LMSKey(text) else { throw ActionError.input(String(localized: .errorLmsKey(text))) }
            return key
        }
        try ctx.editSettings { $0.lms.mark(parsed, handled: handled) }
    }
}
