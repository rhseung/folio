import FolioDomain
import FolioLMS
import Foundation
import Observation

final class MemoryLogins: LMSLogins, @unchecked Sendable {
    private let lock = NSLock()
    private var login: LMSCredentials?
    init(_ login: LMSCredentials? = nil) { self.login = login }
    func read() -> LMSCredentials? { lock.withLock { login } }
    func save(_ login: LMSCredentials) throws { lock.withLock { self.login = login } }
    func remove() { lock.withLock { login = nil } }
}
