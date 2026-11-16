import FolioDomain
import FolioLMS
import Foundation
import Observation

// 앱에서는 iCloud 키체인에, 그 밖에서는 메모리에 둔다. 그래야 어떤 테스트도 실제 항목을 읽거나 쓰지 않는다.
protocol LMSLogins: Sendable {
    func read() -> LMSCredentials?
    func save(_ login: LMSCredentials) throws
    func remove()
}
