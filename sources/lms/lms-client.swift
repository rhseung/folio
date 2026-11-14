import FolioDomain
import Foundation
import Security

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
        try await download("/mod/ubfile/view.php?id=\(file.id)", named: nil, into: folder)
    }

    public func download(_ attachment: LMSAttachment, into folder: URL) async throws -> URL? {
        try await download(attachment.path, named: attachment.name, into: folder)
    }

    // 내려받기를 막은 파일은 원본 대신 Coursemos 뷰어 페이지(HTML)가 온다. 그런 파일은 받지 않고 nil을 돌려준다.
    private func download(_ path: String, named: String?, into folder: URL) async throws -> URL? {
        var (data, response) = try await fetch(path)
        if LMSPages.isLogin(String(decoding: data.prefix(20_000), as: UTF8.self)) {
            try await login()
            (data, response) = try await fetch(path)
        }
        let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard !type.hasPrefix("text/html"), let name = named ?? response.url?.lastPathComponent, !name.isEmpty else { return nil }
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
