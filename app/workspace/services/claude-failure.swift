import FolioAI
import Foundation

// Claude 호출의 실패를 사용자에게 보일 문구로 바꾼다. Claude 패널, 렉처 단원 나누기, 문제 뽑기가 같은 문구를 쓴다.
// `ClaudeError`는 `LocalizedError`를 따르지 않으므로 기본 표기를 그대로 보이면 개발용 글자가 나온다.
enum ClaudeFailure {
    nonisolated static func message(for error: any Error) -> String {
        switch error as? ClaudeError {
        case .missingAPIKey: String(localized: .claudeErrorMissingKey)
        case .http(401, _): String(localized: .claudeErrorAuth)
        case .http(0, let body): String(localized: .claudeErrorFailedBody(String(body.prefix(200))))
        case .http(let status, _): String(localized: .claudeErrorHttp(status))
        case .cli(let exit, ""): String(localized: .claudeErrorCliExit(Int(exit)))
        case .cli(_, let message): String(localized: .claudeErrorCli(String(message.prefix(200))))
        case .signedOut: String(localized: .claudeErrorSignedOut)
        case .refused: String(localized: .claudeErrorRefused)
        case .truncated: String(localized: .claudeErrorTruncated)
        case .invalidOutput, nil: String(localized: .claudeErrorFailedBody(error.localizedDescription))
        }
    }
}
