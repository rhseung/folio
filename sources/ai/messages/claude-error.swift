import FolioDomain
import Foundation

public enum ClaudeError: Error, Equatable {
    case missingAPIKey
    case http(status: Int, body: String)
    // `claude`가 HTTP 응답 없이 실패했다. `exit`은 프로세스의 종료 코드이고 HTTP 상태가 아니다.
    case cli(exit: Int32, message: String)
    case signedOut
    case refused
    case truncated
    case invalidOutput(String)
}
