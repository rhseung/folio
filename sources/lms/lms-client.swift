import FolioDomain
import Foundation
import Security

public struct LMSCredentials: Sendable, Equatable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

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

public enum LMSError: Error, Equatable, Sendable {
    case needsLogin
    case refused
    case http(Int)
}

// 로그인 폼으로 돌아온 페이지는 저장된 로그인으로 한 번 로그인한 뒤 다시 받는다. 틀린 비밀번호를 거듭 보내면 포털
// 계정이 잠길 수 있으므로 두 번째 거절에서 멈춘다.
public actor LMSClient {
    let session: URLSession
    let credentials: @Sendable () -> LMSCredentials?
    let pause: Duration
    private var last: ContinuousClock.Instant?
    private var refused = false

    public init(credentials: @escaping @Sendable () -> LMSCredentials? = LMSCredentialStore.read, pause: Duration = .milliseconds(500)) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": "Folio (personal study app)"]
        self.session = URLSession(configuration: config)
        self.credentials = credentials
        self.pause = pause
    }

    public func page(_ path: String) async throws -> String {
        let html = try await get(path).text
        guard LMSPages.isLogin(html) else { return html }
        try await login()
        let again = try await get(path).text
        if LMSPages.isLogin(again) { throw LMSError.needsLogin }
        return again
    }

    // Moodle은 폼보다 세션 cookie를 먼저 요구하므로 폼을 먼저 받는다.
    public func login() async throws {
        guard !refused, let login = credentials() else { throw LMSError.needsLogin }
        _ = try await get("/login/index.php")
        var request = URLRequest(url: LMS.url("/login/index.php"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.form(["username": login.username, "password": login.password]).utf8)
        let (data, response) = try await send(request)
        let html = String(decoding: data, as: UTF8.self)
        if LMSPages.isLogin(html) || response.url?.path.hasPrefix("/login") == true {
            refused = true
            throw LMSError.refused
        }
    }

    public func download(_ file: LMSFile, into folder: URL) async throws -> URL? {
        let path = "/mod/ubfile/view.php?id=\(file.id)"
        var (data, response) = try await fetch(path)
        if LMSPages.isLogin(String(decoding: data.prefix(20_000), as: UTF8.self)) {
            try await login()
            (data, response) = try await fetch(path)
        }
        let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard !type.hasPrefix("text/html"), let name = response.url?.lastPathComponent, !name.isEmpty else { return nil }
        let target = folder.appending(path: name)
        try data.write(to: target, options: .atomic)
        return target
    }

    private func get(_ path: String) async throws -> (text: String, response: URLResponse) {
        let (data, response) = try await fetch(path)
        return (String(decoding: data, as: UTF8.self), response)
    }

    private func fetch(_ path: String) async throws -> (Data, URLResponse) {
        try await send(URLRequest(url: LMS.url(path)))
    }

    // `URLComponents`는 값 안의 `+`와 `&`를 그대로 두는데, form body에서 이 문자는 공백과 새 필드로 읽힌다. 비밀번호에
    // 둘 중 하나가 들어 있을 수 있다.
    static func form(_ fields: KeyValuePairs<String, String>) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(.init(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
        allowed.insert(charactersIn: "-._~")
        return fields.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if let last { try await Task.sleep(until: last + pause) }
        defer { last = .now }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) { throw LMSError.http(http.statusCode) }
        return (data, response)
    }
}

public enum LMSSync {
    public static func read(_ client: LMSClient, at now: Date) async throws -> LMSSnapshot {
        var snapshot = LMSSnapshot(at: now, classrooms: try LMSPages.classrooms(await client.page("/")))
        for room in snapshot.classrooms {
            snapshot.merge(try await classroom(client, room.id), in: room.id)
        }
        return snapshot
    }

    public static func classroom(_ client: LMSClient, _ id: Int) async throws -> LMSSnapshot {
        LMSSnapshot(
            at: .now,
            assignments: try LMSPages.assignments(await client.page("/mod/assign/index.php?id=\(id)"), classroom: id),
            files: try LMSPages.files(await client.page("/mod/ubfile/index.php?id=\(id)"), classroom: id),
            notices: try LMSPages.notices(await client.page("/mod/ubboard/my.php?mc=\(id)"), classroom: id))
    }
}
