import FolioDomain
import FolioLMS
import Foundation
import Observation

@MainActor @Observable
final class LMSConnection {
    enum Status: Equatable {
        case off
        case idle
        case syncing
        case needsLogin
        // 마지막으로 읽은 내용(기기 캐시)을 그대로 보이고, 다음 주기에 다시 읽는다.
        case offline
        case failed(String)
    }

    private(set) var status: Status
    private(set) var username: String?
    private(set) var snapshot: LMSSnapshot?
    private(set) var viewerOnly: Set<Int> = []
    @ObservationIgnored private var source: any LMSSource
    @ObservationIgnored private let logins: any LMSLogins
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private let cache: LMSCache?

    init(source: (any LMSSource)? = nil, logins: (any LMSLogins)? = nil, cache: LMSCache? = nil) {
        // 테스트, 렌더, 가짜 폴더로 돌린 앱(`FOLIO_GIST`, 창 스냅숏)은 직접 넘기지 않는 한 LMS, 키체인, 기기 캐시에 닿지
        // 않는다. 키체인을 읽으면 허락 창이 떠서 창 스냅숏이 멈춘다.
        let isolated = !Workspace.remembersFolders
        self.logins = logins ?? (isolated ? MemoryLogins() : KeychainLogins())
        self.source = source ?? (isolated ? FixedLMS(snapshot: LMSSnapshot(at: .distantPast)) : Self.live(self.logins))
        live = source == nil && !isolated
        self.cache = cache ?? (live ? LMSCache(file: Self.cacheFile) : nil)
        let login = self.logins.read()
        username = login?.username
        status = login == nil ? .off : .idle
        if source != nil, let fixed = self.source as? FixedLMS, login != nil { snapshot = fixed.snapshot }
        if snapshot == nil, let login { snapshot = self.cache?.read(account: login.username) }
    }

    static var cacheFile: URL { URL.cachesDirectory.appending(path: "Folio/lms-snapshot.json") }

    var isConnected: Bool { username != nil }

    func connect(username: String, password: String) async throws {
        let login = LMSCredentials(username: username.trimmingCharacters(in: .whitespaces), password: password)
        try await source.verify(login)
        // folio:not-an-action the LMS login goes to the keychain
        try logins.save(login)
        // LMS가 거절하면 그 세션은 다시 쓸 수 없으므로, 이전 세션 대신 새 세션을 만든다.
        if live { source = Self.live(logins) }
        if login.username != username { snapshot = cache?.read(account: login.username) }
        self.username = login.username
        status = .idle
    }

    func disconnect() {
        logins.remove()
        if live { source = Self.live(logins) }
        cache?.remove()
        username = nil
        snapshot = nil
        status = .off
    }

    func sync(attachments: @escaping @Sendable (LMSSnapshot) -> [LMSAssignment] = { _ in [] }) async -> LMSSnapshot? {
        guard isConnected, status != .syncing else { return nil }
        status = .syncing
        do {
            let read = try await source.read(attachments: attachments)
            snapshot = read
            status = .idle
            if let username { cache?.write(read, account: username) }
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
        return got
    }

    // 첨부를 하나씩 따로 폴더에 받아, 이름이 같은 두 첨부도 덮어쓰지 않는다.
    func download(_ attachments: [LMSAttachment]) async throws -> [URL] {
        var got: [URL] = []
        for a in attachments {
            if let url = try await source.download(a, into: try LMSDownloads.folder()) { got.append(url) }
        }
        return got
    }

    private static func live(_ logins: any LMSLogins) -> LiveLMS {
        LiveLMS(client: LMSClient(credentials: { logins.read() }))
    }

    static func status(after error: any Error) -> Status {
        switch error {
        case LMSError.needsLogin, LMSError.refused: .needsLogin
        case _ where LMSOffline.contains(error): .offline
        default: .failed(error.localizedDescription)
        }
    }
}
