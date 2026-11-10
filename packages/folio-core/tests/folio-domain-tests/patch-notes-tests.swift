import FolioDomain
import Foundation
import PropertyBased
import Testing

struct PatchNotesTests {
    typealias V = PatchNotes.Version
    typealias Item = PatchNotes.Item

    static let body = """
    노트 옆 칸에 목차를 둡니다(#387).

    ## 패치 노트
    - feat: 노트 옆 칸의 제목 목차
    - feat: 수업 시작 자동 실행 (folio://settings/recording)
    * change : 빠른 추가 칩이 처음부터 흐리게 보임 (folio://today)
    - fix: 수식 말풍선 위와 오른쪽 여백
    - fix: 회차 노트의 링크 (folio://note/6F9619FF-8B86-D011-B42D-00C04FC964FF)
    - feature: 커밋 규칙에 없는 종류는 항목이 아님
    - 새 기능: 번역한 종류도 항목이 아님
    - fix:
    #415 관련 메모는 제목이 아니다
    ### fix
    - fix: 소제목 뒤의 항목

    ## 확인
    - feat: 다른 절의 줄은 항목이 아님

    https://claude.ai/code/session
    """

    @Test func readsTheSectionOfABody() {
        #expect(PatchNotes.items(in: Self.body) == [
            Item(kind: .feat, text: "노트 옆 칸의 제목 목차"),
            Item(kind: .feat, text: "수업 시작 자동 실행", link: .settings(.recording)),
            Item(kind: .change, text: "빠른 추가 칩이 처음부터 흐리게 보임", link: .place(.today)),
            Item(kind: .fix, text: "수식 말풍선 위와 오른쪽 여백"),
            // A note is somebody's own: the link goes, the sentence stays.
            Item(kind: .fix, text: "회차 노트의 링크"),
            // A release groups its lines under `### fix`; the section goes on past it.
            Item(kind: .fix, text: "소제목 뒤의 항목"),
        ])
    }

    @Test func aBodyWithoutTheSectionHasNoItems() {
        #expect(PatchNotes.items(in: "CI만 고쳤습니다.\n\n## 확인\n- fix: 이건 절 밖").isEmpty)
        #expect(PatchNotes.items(in: "").isEmpty)
    }

    @Test func aLaterShapeIsSkippedRatherThanMisread() {
        let now = "## 패치 노트\n\(PatchNotes.marker)\n- feat: 지금 형식"
        #expect(PatchNotes.items(in: now).count == 1)
        let later = "## 패치 노트\n<!-- folio-patch-notes \(PatchNotes.format + 1) -->\n- feat: 다음 형식"
        #expect(PatchNotes.items(in: later).isEmpty)
    }

    @Test func readsVersionsAsTagsWriteThem() {
        #expect(V("0.3.0") == V(0, 3, 0))
        #expect(V("v1.10.2") == V(1, 10, 2))
        #expect(V("0.3") == nil)
        #expect(V("0.3.0-beta") == nil)
        #expect(V("nightly") == nil)
        #expect(V(0, 10, 0) > V(0, 9, 9))
        #expect(V(1, 0, 0).description == "1.0.0")
    }

    @Test func readsGitHubsReleases() throws {
        let json = """
        [
          {"tag_name": "v0.3.0", "draft": true, "prerelease": false, "published_at": null, "body": "## 패치 노트\\n- feat: 초안"},
          {"tag_name": "v0.2.1", "draft": false, "prerelease": false, "published_at": "2026-11-08T03:00:00Z",
           "body": "## 패치 노트\\n<!-- folio-patch-notes 1 -->\\n\\n### fix\\n- fix: 칸 닫기\\n\\n## 머지된 PR\\n- fix: x (#369)"},
          {"tag_name": "v0.2.0", "draft": false, "prerelease": false, "published_at": "2026-11-07T03:00:00Z",
           "body": "## 패치 노트\\r\\n- feat: 창 탭\\r\\n"},
          {"tag_name": "v0.2.0-rc1", "draft": false, "prerelease": true, "published_at": "2026-11-06T03:00:00Z", "body": ""},
          {"tag_name": "test", "draft": false, "prerelease": false, "published_at": "2026-11-05T03:00:00Z", "body": null}
        ]
        """
        let releases = try PatchNotes.releases(fromGitHub: Data(json.utf8))
        #expect(releases.map(\.version) == [V(0, 2, 1), V(0, 2, 0)])
        #expect(releases[0].items == [Item(kind: .fix, text: "칸 닫기")])
        #expect(releases[1].items == [Item(kind: .feat, text: "창 탭")])
        #expect(releases[0].date == Date(timeIntervalSince1970: 1_794_106_800))
    }

    // MARK: After an update

    static func release(_ v: V, _ kinds: PatchNotes.Kind...) -> PatchNotes.Release {
        PatchNotes.Release(version: v, items: kinds.enumerated().map { Item(kind: $1, text: "\(v) \($0)") })
    }

    static let feed: [PatchNotes.Release] = [
        release(V(0, 4, 0), .feat),
        release(V(0, 3, 1), .fix, .fix),
        release(V(0, 3, 0), .feat, .feat, .change, .fix),
        release(V(0, 2, 1), .fix),
        release(V(0, 2, 0), .feat, .change),
    ]

    @Test func firstLaunchAndNoUpdateShowNothing() {
        #expect(PatchNotes.step(seen: nil, current: V(0, 3, 0), feed: .notLoaded, busy: false) == .markSeen)
        #expect(PatchNotes.step(seen: V(0, 3, 0), current: V(0, 3, 0), feed: .notLoaded, busy: false) == .nothing)
        // An older app opened after a newer one.
        #expect(PatchNotes.step(seen: V(0, 4, 0), current: V(0, 3, 0), feed: .notLoaded, busy: false) == .nothing)
    }

    @Test func anUpdateAsksGitHubAndWaitsWhenItFails() {
        #expect(PatchNotes.step(seen: V(0, 2, 0), current: V(0, 3, 0), feed: .notLoaded, busy: false) == .fetch)
        #expect(PatchNotes.step(seen: V(0, 2, 0), current: V(0, 3, 0), feed: .failed, busy: false) == .wait)
    }

    @Test func aVersionWithOnlyFixesIsSeenWithoutASheet() {
        #expect(PatchNotes.step(seen: V(0, 3, 0), current: V(0, 3, 1), feed: .loaded(Self.feed), busy: false) == .markSeen)
    }

    @Test func anUnpublishedReleaseWaits() {
        let published = Array(Self.feed.dropFirst())
        #expect(PatchNotes.step(seen: V(0, 3, 1), current: V(0, 4, 0), feed: .loaded(published), busy: false) == .wait)
    }

    @Test func aClassOrARecordingPutsTheSheetOff() {
        #expect(PatchNotes.step(seen: V(0, 2, 1), current: V(0, 3, 0), feed: .loaded(Self.feed), busy: true) == .wait)
        // Nothing to show is settled at once, class or not.
        #expect(PatchNotes.step(seen: V(0, 3, 0), current: V(0, 3, 1), feed: .loaded(Self.feed), busy: true) == .markSeen)
    }

    @Test func skippedVersionsShowOneSheet() {
        let step = PatchNotes.step(seen: V(0, 2, 0), current: V(0, 3, 1), feed: .loaded(Self.feed), busy: false)
        guard case .show(let s) = step else { Issue.record("\(step)"); return }
        #expect(s.releases.map(\.version) == [V(0, 3, 1), V(0, 3, 0), V(0, 2, 1)])
        #expect(s.latest.version == V(0, 3, 1))
        #expect(s.since == V(0, 2, 0))
        #expect(s.items.map(\.text) == ["0.3.0 0", "0.3.0 1"])
        #expect(s.rest == [PatchNotes.Count(kind: .fix, count: 4), PatchNotes.Count(kind: .change, count: 1)])
    }

    @Test func theSheetKeepsSixNewFeaturesAndCountsTheRest() throws {
        let big = PatchNotes.Release(version: V(1, 0, 0), items: (0..<9).map { Item(kind: .feat, text: "\($0)") })
        let s = try #require(PatchNotes.summary([big], since: V(0, 9, 0)))
        #expect(s.items.count == PatchNotes.sheetLimit)
        #expect(s.rest == [PatchNotes.Count(kind: .feat, count: 3)])
    }

    // MARK: The page

    @Test func thePageListsWhatThisAppHasAndFilters() {
        let history = PatchNotes.history(Self.feed, upTo: V(0, 3, 0))
        #expect(history.map(\.version) == [V(0, 3, 0), V(0, 2, 1), V(0, 2, 0)])
        let fixes = PatchNotes.filter(history, kind: .fix, query: "")
        #expect(fixes.map(\.version) == [V(0, 3, 0), V(0, 2, 1)])
        #expect(fixes.allSatisfy { $0.items.allSatisfy { $0.kind == .fix } })
        #expect(PatchNotes.filter(history, kind: nil, query: "0.2.1").map(\.version) == [V(0, 2, 1)])
        #expect(PatchNotes.filter(history, kind: .feat, query: "0.2.1").isEmpty)
        let ordered = PatchNotes.ordered(PatchNotes.items(in: Self.body))
        #expect(ordered.map(\.kind) == [.feat, .feat, .fix, .fix, .fix, .change])
        #expect(ordered.filter { $0.kind == .fix }.map(\.text) == ["수식 말풍선 위와 오른쪽 여백", "회차 노트의 링크", "소제목 뒤의 항목"])
    }

    // MARK: Properties

    static let kind = Gen.element(of: PatchNotes.Kind.allCases).map { $0! }
    /// Hangul, Latin, digits and punctuation, brackets included, on one line.
    static let text = Gen.oneOf(Gen.character(in: "가"..."힣"), Gen.character(in: " "..."~")).string(of: 0...24)
    static let places: [AppLink?] = [nil] + AppLink.Kind.allCases.filter(\.isPlace).flatMap { kind -> [AppLink] in
        kind == .settings ? [.settings(nil)] + AppLink.SettingsPage.allCases.map { .settings($0) } : [.place(kind)]
    }
    static let link = Gen.element(of: Self.places).map { $0 ?? nil }
    static let version = zip(Gen.int(in: 0...2), Gen.int(in: 0...3), Gen.int(in: 0...3)).map { V($0, $1, $2) }
    static let releases = zip(Self.version, Self.kind.array(of: 0...5)).array(of: 0...8).map { rows -> [PatchNotes.Release] in
        // One release per version, as tags are.
        var seen = Set<V>()
        return rows.compactMap { v, kinds in
            guard seen.insert(v).inserted else { return nil }
            return PatchNotes.Release(version: v, items: kinds.enumerated().map { Item(kind: $1, text: "\(v)-\($0)") })
        }
    }

    @Test func anItemReadsBackAsWritten() async {
        await propertyCheck(input: Self.kind, Self.text, Self.link) { kind, text, link in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.contains("(folio://") else { return }
            let item = Item(kind: kind, text: trimmed, link: link)
            #expect(PatchNotes.item(PatchNotes.line(item)) == item)
            #expect(PatchNotes.items(in: "## 패치 노트\n" + PatchNotes.line(item)) == [item])
        }
    }

    @Test func theSheetShowsOnlyAnUpdatesNewFeatures() async {
        await propertyCheck(input: Self.releases, Self.version, Self.version) { releases, seen, current in
            let step = PatchNotes.step(seen: seen, current: current, feed: .loaded(releases), busy: false)
            guard case .show(let s) = step else {
                if case .markSeen = step {
                    #expect(!PatchNotes.between(releases, after: seen, upTo: current).contains { $0.hasNewFeature })
                }
                return
            }
            #expect(seen < current)
            #expect(s.latest.version == current)
            #expect(s.releases.allSatisfy { seen < $0.version && $0.version <= current })
            #expect(s.releases.contains { $0.hasNewFeature })
            #expect(!s.items.isEmpty && s.items.count <= PatchNotes.sheetLimit && s.items.allSatisfy { $0.kind == .feat })
            // Shown and counted, every item of every unseen version is accounted for once.
            let total = s.releases.reduce(0) { $0 + $1.items.count }
            #expect(s.items.count + s.rest.reduce(0) { $0 + $1.count } == total)
        }
    }

    @Test func filteringOnlyNarrows() async {
        await propertyCheck(input: Self.releases, Self.kind.optional(), Self.text) { releases, kind, query in
            let filtered = PatchNotes.filter(releases, kind: kind, query: query)
            for release in filtered {
                guard let original = releases.first(where: { $0.version == release.version }) else {
                    Issue.record("\(release.version) is not one of the releases")
                    continue
                }
                #expect(!release.items.isEmpty)
                #expect(release.items.allSatisfy { original.items.contains($0) })
                if let kind { #expect(release.items.allSatisfy { $0.kind == kind }) }
            }
            if kind == nil, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                #expect(filtered == releases.filter { !$0.items.isEmpty })
            }
        }
    }
}
