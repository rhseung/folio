import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class ReleaseNotes {
    private(set) var feed: PatchNotes.Feed = .notLoaded
    private(set) var loading = false
    var ask: PatchNotes.Summary?
    // 창이 시트를 가져갈 때 정해야, 닫기 전에 다음 분의 확인이 시트를 다시 띄우지 않는다.
    private var shown = false
    let current: PatchNotes.Version
    @ObservationIgnored private let source: any ReleaseFeed
    @ObservationIgnored private let defaults: UserDefaults
    // 디버그 빌드는 설치한 앱과 기본값을 함께 쓴다(같은 bundle ID). 버전을 올린 뒤 빌드한 디버그 앱은 릴리스가 나오기
    // 전에 그 버전을 본 것으로 표시하고, 설치한 앱은 그 버전을 영영 보이지 않게 된다.
    @ObservationIgnored let prompts: Bool

    static let seenKey = "folio.patchNotesSeen"

    init(
        source: (any ReleaseFeed)? = nil, defaults: UserDefaults = .standard, current: PatchNotes.Version = ReleaseNotes.appVersion,
        prompts: Bool = ReleaseNotes.promptsByDefault
    ) {
        // 테스트나 렌더는 피드를 넘기지 않는 한 GitHub에 닿지 않는다.
        self.source = source ?? (LocalFolders.isIsolated() ? ReleaseList(list: []) as any ReleaseFeed : GitHubReleases())
        self.defaults = defaults
        self.current = current
        self.prompts = prompts
    }

    // `mise run generate`가 `FolioVersion`에서 Info.plist를 채운다.
    nonisolated static var appVersion: PatchNotes.Version {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(PatchNotes.Version.init)
            ?? PatchNotes.Version(FolioVersion.marketing) ?? PatchNotes.Version(0, 0, 0)
    }

    nonisolated static var promptsByDefault: Bool {
        #if DEBUG
        false
        #else
        !LocalFolders.isIsolated()
        #endif
    }

    var seen: PatchNotes.Version? {
        defaults.string(forKey: Self.seenKey).flatMap(PatchNotes.Version.init)
    }

    func markSeen() {
        defaults.set(current.description, forKey: Self.seenKey)
    }

    func load() async {
        guard feed == .notLoaded else { return }
        await reload()
    }

    func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            feed = .loaded(try await source.releases())
        } catch {
            feed = .failed
        }
    }

    func check(busy: Bool) async {
        guard prompts, !shown, ask == nil else { return }
        var step = PatchNotes.step(seen: seen, current: current, feed: feed, busy: busy)
        if step == .fetch {
            await load()
            step = PatchNotes.step(seen: seen, current: current, feed: feed, busy: busy)
        }
        switch step {
        case .nothing, .wait, .fetch: break
        case .markSeen: markSeen()
        case .show(let summary): if !shown, ask == nil { ask = summary }
        }
    }

    func take() -> PatchNotes.Summary? {
        guard let ask else { return nil }
        self.ask = nil
        shown = true
        return ask
    }

    var history: [PatchNotes.Release]? {
        guard case .loaded(let all) = feed else { return nil }
        return PatchNotes.history(all, upTo: current)
    }

    var release: PatchNotes.Release? { history?.first { $0.version == current } }
}

extension Workspace {
    var updateSheetWaits: Bool {
        recorder.isActive || classStartAsk != nil || ongoingClass(at: liveNow) != nil
    }
}
