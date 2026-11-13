import FolioDomain
import FolioLMS
import Foundation
import Observation

/// Where LMS pages come from: the school's LMS in the app, a fixed snapshot in tests, previews and renders.
protocol LMSSource: Sendable {
    func verify(_ login: LMSCredentials) async throws
    func read() async throws -> LMSSnapshot
    func download(_ file: LMSFile, into folder: URL) async throws -> URL?
}

/// Where the login is kept: iCloud Keychain in the app, memory elsewhere, so no test reads or writes the real item.
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

/// The school's LMS through one web session, logging in again with the saved login when it ends.
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

    func verify(_ login: LMSCredentials) async throws {}
    func read() async throws -> LMSSnapshot { snapshot }
    func download(_ file: LMSFile, into folder: URL) async throws -> URL? { nil }
}

/// The LMS as this device last read it. App-wide like `ReleaseNotes`: one sync however many windows are open. What
/// was read is kept in memory only; what was decided about it (classrooms seen, items handled) is in settings.json.
@MainActor @Observable
final class LMSConnection {
    enum Status: Equatable {
        case off
        case idle
        case syncing
        /// The saved login was refused or is gone: the settings tab asks to connect again.
        case needsLogin
        case failed(String)
    }

    private(set) var status: Status
    private(set) var username: String?
    private(set) var snapshot: LMSSnapshot?
    /// Files the LMS shows only in its viewer, found when adding one was tried.
    private(set) var viewerOnly: Set<Int> = []
    @ObservationIgnored private var source: any LMSSource
    @ObservationIgnored private let logins: any LMSLogins
    @ObservationIgnored private let live: Bool

    init(source: (any LMSSource)? = nil, logins: (any LMSLogins)? = nil) {
        // Nothing reaches the LMS or the keychain from a test or a render unless it hands them over.
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

    /// Tries the login before keeping it, so a typo is told at once instead of at the next sync.
    func connect(username: String, password: String) async throws {
        let login = LMSCredentials(username: username.trimmingCharacters(in: .whitespaces), password: password)
        try await source.verify(login)
        // folio:not-an-action the LMS login goes to the keychain
        try logins.save(login)
        // A new session: the old one may have been refused, and refusing stops it for good.
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

    /// The snapshot read, or nil when nothing was (not connected, already syncing, or failed: `status` says which).
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

    /// The file downloaded into a folder of its own under the name `Lectures` gives it, or nil when the LMS shows it
    /// only in its viewer.
    func download(_ file: LMSFile) async throws -> URL? {
        let folder = URL.temporaryDirectory.appending(path: "Folio-LMS/\(UUID().uuidString)", directoryHint: .isDirectory)
        // folio:not-an-action a temporary folder; `lms accept` imports from it
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let got = try await source.download(file, into: folder) else {
            viewerOnly.insert(file.id)
            return nil
        }
        let named = folder.appending(path: file.lectureName(got.lastPathComponent))
        // folio:not-an-action renamed inside the temporary folder
        if named != got { try FileManager.default.moveItem(at: got, to: named) }
        return named
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
