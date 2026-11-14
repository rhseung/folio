import FolioDomain
import Foundation
import Security

public enum LMSCredentialStore {
    static let service = "com.rhseung.folio.lms"

    static var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }

    public static func read() -> LMSCredentials? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let found = item as? [String: Any],
            let account = found[kSecAttrAccount as String] as? String, let data = found[kSecValueData as String] as? Data
        else { return nil }
        return LMSCredentials(username: account, password: String(decoding: data, as: UTF8.self))
    }

    public static func save(_ credentials: LMSCredentials) throws {
        remove()
        var q = base
        q[kSecAttrAccount as String] = credentials.username
        q[kSecValueData as String] = Data(credentials.password.utf8)
        q[kSecAttrLabel as String] = "Folio GIST LMS"
        q[kSecAttrSynchronizable as String] = true
        var status = SecItemAdd(q as CFDictionary, nil)
        // 팀 없이 서명한 앱(Sign to Run Locally)은 동기화되는 항목을 쓰지 못할 수 있다. 그때는 로그인을 아예 남기지
        // 않는 대신 이 기기에만 남기고, 서명한 빌드는 다음 연결 때 동기화되는 항목으로 쓴다.
        if status == errSecMissingEntitlement {
            q[kSecAttrSynchronizable as String] = false
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    public static func remove() {
        SecItemDelete(base as CFDictionary)
    }
}
