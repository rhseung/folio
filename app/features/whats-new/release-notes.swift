import FolioDomain
import Foundation
import Observation

/// Where the releases come from: GitHub in the app, a fixed list in tests, previews and renders.
protocol ReleaseFeed: Sendable {
    func releases() async throws -> [PatchNotes.Release]
}

/// The public repository's releases, without a token. Online only (#415): the notes aren't bundled, so a PR body edited
/// after its merge still reaches the app through its release.
struct GitHubReleases: ReleaseFeed {
    // One page: a hundred releases is years of them. Past that the oldest drop off the page, never the newest.
    static let url = URL(string: "https://api.github.com/repos/rhseung/folio/releases?per_page=100")!

    func releases() async throws -> [PatchNotes.Release] {
        var request = URLRequest(url: Self.url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try PatchNotes.releases(fromGitHub: data)
    }
}

struct ReleaseList: ReleaseFeed {
    var list: [PatchNotes.Release]
    var fails = false

    func releases() async throws -> [PatchNotes.Release] {
        if fails { throw URLError(.notConnectedToInternet) }
        return list
    }
}

/// The releases, asked for once a launch, and the sheet an update brings (`WhatsNewPrompt`). App-wide, so one sheet
/// shows however many windows are open.
@MainActor @Observable
final class ReleaseNotes {
    private(set) var feed: PatchNotes.Feed = .notLoaded
    private(set) var loading = false
    /// The sheet waiting for a window to take it.
    var ask: PatchNotes.Summary?
    /// Set when a window takes the sheet, so the minute's next check doesn't bring it again before it is closed.
    private var shown = false
    let current: PatchNotes.Version
    @ObservationIgnored private let source: any ReleaseFeed
    @ObservationIgnored private let defaults: UserDefaults
    /// Off in debug builds and in tests, previews and renders. A debug build shares the installed app's defaults (one
    /// bundle ID), and one built after a version bump would mark that version seen before its release was out: the
    /// installed app would then never show it.
    @ObservationIgnored let prompts: Bool

    /// Per device, not in GIST's settings.json: what this device has shown is no fact about the student's data.
    static let seenKey = "folio.patchNotesSeen"

    init(source: (any ReleaseFeed)? = nil, defaults: UserDefaults = .standard, current: PatchNotes.Version = ReleaseNotes.appVersion,
         prompts: Bool = ReleaseNotes.promptsByDefault) {
        // Nothing reaches GitHub from a test or a render unless it hands over a feed.
        self.source = source ?? (LocalFolders.isIsolated() ? ReleaseList(list: []) as any ReleaseFeed : GitHubReleases())
        self.defaults = defaults
        self.current = current
        self.prompts = prompts
    }

    /// From the Info.plist, which `mise run generate` fills from `FolioVersion`.
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

    /// Once a launch: a failure waits for the next one (or the page's 다시 시도), not for the next minute.
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

    /// At launch and as the minute turns. `busy`: a class or a recording under way, which a sheet would cover.
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

    /// A window shows the sheet; the others leave it.
    func take() -> PatchNotes.Summary? {
        guard let ask else { return nil }
        self.ask = nil
        shown = true
        return ask
    }

    /// The releases this app's version has, newest first; nil until loaded or when GitHub couldn't be reached.
    var history: [PatchNotes.Release]? {
        guard case .loaded(let all) = feed else { return nil }
        return PatchNotes.history(all, upTo: current)
    }

    var release: PatchNotes.Release? { history?.first { $0.version == current } }
}

extension Workspace {
    /// A class under way or a recording: the moment the update's sheet would get in the way.
    var updateSheetWaits: Bool {
        recorder.isActive || classStartAsk != nil || ongoingClass(at: liveNow) != nil
    }
}

#if DEBUG
extension ReleaseList {
    /// What previews and renders show: three releases written as the release script writes them, read the way GitHub's
    /// would be.
    static let sample: [PatchNotes.Release] = [
        PatchNotes.Release(version: PatchNotes.Version(0, 3, 0), date: Date(timeIntervalSince1970: 1_794_193_200), items: PatchNotes.items(in: """
        ## 패치 노트
        - feat: 노트 옆 칸의 제목 목차와 [TOC] 블록
        - feat: 수업 시각에 녹음, 러프 노트, 렉처 자동 열기 (folio://settings/recording)
        - feat: 수식 안에서 \\만 쳐도 뜨는 기호와 스니펫 목록
        - feat: 미리보기 그림 크게 보기
        - change: 빠른 추가의 과목, 마감, 반복 칩이 처음부터 흐리게 보임 (folio://today)
        - change: 편집 보기의 수식 말풍선을 미리보기와 같은 KaTeX로 그림
        - fix: 수식 말풍선 위와 오른쪽의 빈 여백
        - fix: 여러 줄 칸이 글을 따라 12줄까지 늘어남
        """)),
        PatchNotes.Release(version: PatchNotes.Version(0, 2, 1), date: Date(timeIntervalSince1970: 1_794_106_800), items: PatchNotes.items(in: """
        ## 패치 노트
        - change: 칸 경계를 끌면 부드럽게 따라옴
        - fix: 칸이 둘 이상인 탭에서 칸을 닫으면 앱이 꺼지던 문제
        - fix: 표 칸 안의 [[링크|이름]]이 잘리던 문제
        """)),
        PatchNotes.Release(version: PatchNotes.Version(0, 2, 0), date: Date(timeIntervalSince1970: 1_794_020_400), items: PatchNotes.items(in: """
        ## 패치 노트
        - feat: 툴바 줄의 창 탭
        - feat: 한 탭 안에서 두 화면을 나란히 보는 칸 나누기
        - feat: 오늘 화면의 수업 정리 시트 (folio://today)
        - change: 스크롤 막대 대신 넘길 것이 남은 쪽 가장자리를 흐림
        - fix: 단원 나누기 화면에서 취소하면 앱이 꺼지던 문제
        """)),
    ]
}
#endif
