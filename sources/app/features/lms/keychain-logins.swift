import FolioDomain
import FolioLMS
import Foundation
import Observation

struct KeychainLogins: LMSLogins {
    func read() -> LMSCredentials? { LMSCredentialStore.read() }
    // folio:not-an-action the LMS login goes to the keychain
    func save(_ login: LMSCredentials) throws { try LMSCredentialStore.save(login) }
    func remove() { LMSCredentialStore.remove() }
}
