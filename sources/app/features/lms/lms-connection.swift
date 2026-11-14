import FolioDomain
import FolioLMS
import Foundation
import Observation

protocol LMSSource: Sendable {
    func verify(_ login: LMSCredentials) async throws
    func read() async throws -> LMSSnapshot
    func download(_ file: LMSFile, into folder: URL) async throws -> URL?
}

// 앱에서는 iCloud 키체인에, 그 밖에서는 메모리에 둔다. 그래야 어떤 테스트도 실제 항목을 읽거나 쓰지 않는다.
protocol LMSLogins: Sendable {
    func read() -> LMSCredentials?
    func save(_ login: LMSCredentials) throws
    func remove()
}

struct KeychainLogins: LMSLogins {
    func read() -> LMSCredentials? { LMSCredentialStore.read() }
    // folio:not-an-action the LMS login goes to the keychain
    func save(_ login: LMSCredentials) throws { try LMSCredentialStore.save(login) }
    func remove() { LMSCredentialStore.remove() }
}

final class MemoryLogins: LMSLogins, @unchecked Sendable {
    private let lock = NSLock()
    private var login: LMSCredentials?
    init(_ login: LMSCredentials? = nil) { self.login = login }
    func read() -> LMSCredentials? { lock.withLock { login } }
    func save(_ login: LMSCredentials) throws { lock.withLock { self.login = login } }
    func remove() { lock.withLock { login = nil } }
}

struct LiveLMS: LMSSource {
    let client: LMSClient

    func verify(_ login: LMSCredentials) async throws {
        try await LMSClient(credentials: { login }).login()
    }

    func read() async throws -> LMSSnapshot { try await LMSSync.read(client, at: .now) }

    func download(_ file: LMSFile, into folder: URL) async throws -> URL? { try await client.download(file, into: folder) }
}

struct FixedLMS: LMSSource {
    var snapshot: LMSSnapshot

    func verify(_ login: LMSCredentials) throws {}
    func read() throws -> LMSSnapshot { snapshot }
    func download(_ file: LMSFile, into folder: URL) throws -> URL? { nil }
}

@MainActor @Observable
final class LMSConnection {
    enum Status: Equatable {
        case off
        case idle
        case syncing
        case needsLogin
        case failed(String)
    }

    private(set) var status: Status
    private(set) var username: String?
    private(set) var snapshot: LMSSnapshot?
    private(set) var viewerOnly: Set<Int> = []
    @ObservationIgnored private var source: any LMSSource
    @ObservationIgnored private let logins: any LMSLogins
    @ObservationIgnored private let live: Bool

    init(source: (any LMSSource)? = nil, logins: (any LMSLogins)? = nil) {
        // 테스트나 렌더는 직접 넘기지 않는 한 LMS와 키체인에 닿지 않는다.
        let isolated = LocalFolders.isIsolated()
        self.logins = logins ?? (isolated ? MemoryLogins() : KeychainLogins())
        self.source = source ?? (isolated ? FixedLMS(snapshot: LMSSnapshot(at: .distantPast)) : Self.live(self.logins))
        live = source == nil && !isolated
        let login = self.logins.read()
        username = login?.username
        status = login == nil ? .off : .idle
        if source != nil, let fixed = self.source as? FixedLMS, login != nil { snapshot = fixed.snapshot }
    }

    var isConnected: Bool { username != nil }

    func connect(username: String, password: String) async throws {
        let login = LMSCredentials(username: username.trimmingCharacters(in: .whitespaces), password: password)
        try await source.verify(login)
        // folio:not-an-action the LMS login goes to the keychain
        try logins.save(login)
        // LMS가 거절하면 그 세션은 다시 쓸 수 없으므로, 이전 세션 대신 새 세션을 만든다.
        if live { source = Self.live(logins) }
        self.username = login.username
        status = .idle
    }

    func disconnect() {
        logins.remove()
        if live { source = Self.live(logins) }
        username = nil
        snapshot = nil
        status = .off
    }

    func sync() async -> LMSSnapshot? {
        guard isConnected, status != .syncing else { return nil }
        status = .syncing
        do {
            let read = try await source.read()
            snapshot = read
            status = .idle
            return read
        } catch {
            status = Self.status(after: error)
            return nil
        }
    }

    func download(_ file: LMSFile) async throws -> URL? {
        let folder = try LMSDownloads.folder()
        guard let got = try await source.download(file, into: folder) else {
            viewerOnly.insert(file.id)
            return nil
        }
        return try LMSDownloads.rename(got, to: file.lectureName(got.lastPathComponent))
    }

    private static func live(_ logins: any LMSLogins) -> LiveLMS {
        LiveLMS(client: LMSClient(credentials: { logins.read() }))
    }

    static func status(after error: any Error) -> Status {
        switch error {
        case LMSError.needsLogin, LMSError.refused: .needsLogin
        default: .failed(error.localizedDescription)
        }
    }
}
