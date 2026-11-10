import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct WhatsNewModelTests {
    typealias V = PatchNotes.Version

    static let releases = [
        PatchNotes.Release(version: V(0, 3, 0), items: [
            PatchNotes.Item(kind: .feat, text: "노트 목차"),
            PatchNotes.Item(kind: .fix, text: "수식 말풍선 여백"),
        ]),
        PatchNotes.Release(version: V(0, 2, 1), items: [PatchNotes.Item(kind: .fix, text: "칸 닫기")]),
        PatchNotes.Release(version: V(0, 2, 0), items: [PatchNotes.Item(kind: .feat, text: "창 탭", link: .place(.today))]),
    ]

    /// A store of its own, so no test reads or writes the app's real defaults.
    func defaults() throws -> UserDefaults {
        let name = "folio.tests.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        d.removePersistentDomain(forName: name)
        return d
    }

    func notes(seen: V?, current: V = V(0, 3, 0), fails: Bool = false, defaults: UserDefaults) -> ReleaseNotes {
        if let seen { defaults.set(seen.description, forKey: ReleaseNotes.seenKey) }
        return ReleaseNotes(source: ReleaseList(list: Self.releases, fails: fails), defaults: defaults, current: current, prompts: true)
    }

    @Test func aFirstLaunchIsSeenWithoutASheet() async throws {
        let d = try defaults()
        let n = notes(seen: nil, defaults: d)
        await n.check(busy: false)
        #expect(n.ask == nil)
        #expect(n.seen == V(0, 3, 0))
        // Nothing needed the releases.
        #expect(n.feed == .notLoaded)
    }

    @Test func anUpdateShowsOneSheetOnce() async throws {
        let d = try defaults()
        let n = notes(seen: V(0, 2, 0), defaults: d)
        await n.check(busy: false)
        let ask = try #require(n.ask)
        #expect(ask.releases.map(\.version) == [V(0, 3, 0), V(0, 2, 1)])
        #expect(ask.items.map(\.text) == ["노트 목차"])
        #expect(n.take() == ask)
        #expect(n.take() == nil)
        // Taken but not yet closed: the next minute's check doesn't bring it again.
        await n.check(busy: false)
        #expect(n.ask == nil)
        // Closing marks it seen, for the next launch too.
        n.markSeen()
        let next = ReleaseNotes(source: ReleaseList(list: Self.releases), defaults: d, current: V(0, 3, 0), prompts: true)
        await next.check(busy: false)
        #expect(next.ask == nil)
    }

    @Test func aClassPutsTheSheetOffUntilItEnds() async throws {
        let n = notes(seen: V(0, 2, 1), defaults: try defaults())
        await n.check(busy: true)
        #expect(n.ask == nil)
        #expect(n.seen == V(0, 2, 1))
        await n.check(busy: false)
        #expect(n.ask?.latest.version == V(0, 3, 0))
    }

    @Test func offlineWaitsForTheNextLaunch() async throws {
        let n = notes(seen: V(0, 2, 0), fails: true, defaults: try defaults())
        await n.check(busy: false)
        #expect(n.ask == nil)
        #expect(n.feed == .failed)
        #expect(n.seen == V(0, 2, 0))
    }

    @Test func onlyFixesAreSeenQuietly() async throws {
        let n = notes(seen: V(0, 2, 0), current: V(0, 2, 1), defaults: try defaults())
        await n.check(busy: false)
        #expect(n.ask == nil)
        #expect(n.seen == V(0, 2, 1))
    }

    @Test func debugBuildsAndTestsNeverPrompt() async throws {
        let d = try defaults()
        d.set("0.1.0", forKey: ReleaseNotes.seenKey)
        let n = ReleaseNotes(source: ReleaseList(list: Self.releases), defaults: d, current: V(0, 3, 0))
        await n.check(busy: false)
        #expect(n.ask == nil)
        #expect(n.seen == V(0, 1, 0))
    }

    // MARK: The page

    func makeModel(fails: Bool = false) throws -> WhatsNewModel {
        let workspace = try fixtureWorkspace()
        workspace.releaseNotes = ReleaseNotes(source: ReleaseList(list: Self.releases, fails: fails), defaults: try defaults(), current: V(0, 2, 1),
                                              prompts: false)
        return WhatsNewModel(workspace: workspace)
    }

    @Test func thePageListsThisVersionsReleasesWithItOpen() async throws {
        let model = try makeModel()
        #expect(model.state == .loading)
        await model.load()
        guard case .releases(let shown) = model.state else { Issue.record("\(model.state)"); return }
        // 0.3.0 is for a newer app.
        #expect(shown.map(\.version) == [V(0, 2, 1), V(0, 2, 0)])
        #expect(model.isOpen(shown[0]) && !model.isOpen(shown[1]))
        model.toggle(shown[1])
        model.toggle(shown[0])
        #expect(!model.isOpen(shown[0]) && model.isOpen(shown[1]))
        #expect(model.counts(shown[0]) == [PatchNotes.Count(kind: .fix, count: 1)])
    }

    @Test func searchingOpensEveryMatch() async throws {
        let model = try makeModel()
        await model.load()
        model.query = "창"
        guard case .releases(let shown) = model.state else { Issue.record("\(model.state)"); return }
        #expect(shown.map(\.version) == [V(0, 2, 0)])
        #expect(model.isOpen(shown[0]))
        model.kind = .fix
        #expect(model.state == .noMatch)
        #expect(model.noMatch == "‘창’에 맞는 항목 없음 (fix)")
    }

    @Test func offlineSaysSoAndRetries() async throws {
        let model = try makeModel(fails: true)
        await model.load()
        #expect(model.state == .unavailable)
    }
}
