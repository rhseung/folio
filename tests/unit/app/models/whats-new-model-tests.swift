import FolioDomain
import Foundation
import Testing

@testable import Folio

@MainActor
struct WhatsNewModelTests {
    typealias V = PatchNotes.Version

    static let releases = [
        PatchNotes.Release(
            version: V(0, 3, 0),
            items: [
                PatchNotes.Item(kind: .feat, text: "노트 목차"),
                PatchNotes.Item(kind: .fix, text: "수식 말풍선 여백"),
            ]),
        PatchNotes.Release(version: V(0, 2, 1), items: [PatchNotes.Item(kind: .fix, text: "칸 닫기")]),
        PatchNotes.Release(version: V(0, 2, 0), items: [PatchNotes.Item(kind: .feat, text: "창 탭", link: .place(.today))]),
    ]

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
        #expect(n.feed == .notLoaded)
    }

    @Test func anUpdateShowsOneSheetOnce() async throws {
        let d = try defaults()
        let n = notes(seen: V(0, 2, 0), defaults: d)
        await n.check(busy: false)
        let ask = try #require(n.ask)
        #expect(ask.releases.map(\.version) == [V(0, 3, 0), V(0, 2, 1)])
        #expect(ask.items.map(\.text) == ["노트 목차", "수식 말풍선 여백", "칸 닫기"])
        #expect(n.take() == ask)
        #expect(n.take() == nil)

        await n.check(busy: false)
        #expect(n.ask == nil)

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

    func makeModel(current: V = V(0, 2, 1), fails: Bool = false) throws -> WhatsNewModel {
        let workspace = try fixtureWorkspace()
        workspace.releaseNotes = ReleaseNotes(
            source: ReleaseList(list: Self.releases, fails: fails), defaults: try defaults(), current: current, prompts: false)
        return WhatsNewModel(workspace: workspace)
    }

    @Test func thePageFoldsPatchesUnderTheirMinorWithThisOneOpen() async throws {
        let model = try makeModel()
        #expect(model.state == .loading)
        await model.load()
        guard case .series(let shown) = model.state else { Issue.record("\(model.state)"); return }
        #expect(shown.map(\.name) == ["0.2"])
        #expect(shown[0].releases.map(\.version) == [V(0, 2, 1), V(0, 2, 0)])
        #expect(model.isOpen(shown[0]) && model.isCurrent(shown[0]) && model.showsReleases(shown[0]))
        #expect(model.items(shown[0].latest).map(\.text) == ["칸 닫기"])
    }

    @Test func olderMinorsStayFoldedUntilToggled() async throws {
        let model = try makeModel(current: V(0, 3, 0))
        await model.load()
        guard case .series(let shown) = model.state else { Issue.record("\(model.state)"); return }
        #expect(shown.map(\.name) == ["0.3", "0.2"])
        #expect(model.isOpen(shown[0]) && !model.isOpen(shown[1]))
        #expect(!model.showsReleases(shown[0]))

        model.toggle(shown[1])
        model.toggle(shown[0])
        #expect(!model.isOpen(shown[0]) && model.isOpen(shown[1]))
        #expect(!model.isCurrent(shown[1]))
    }

    @Test func aSeriesSpansTheDaysOfItsReleases() throws {
        let model = try makeModel()
        let day = Date(timeIntervalSince1970: 1_794_020_400)
        func release(_ v: V, _ date: Date?) -> PatchNotes.Release { PatchNotes.Release(version: v, date: date, items: []) }
        let calendar = model.workspace.calendar
        let first = WhatsNewModel.day(day, calendar: calendar)
        let later = WhatsNewModel.day(day.addingTimeInterval(2 * 86_400), calendar: calendar)
        let spanning = PatchNotes.series([release(V(0, 5, 1), day.addingTimeInterval(2 * 86_400)), release(V(0, 5, 0), day)])[0]
        #expect(model.days(spanning) == "\(first) – \(later)")
        let sameDay = PatchNotes.series([release(V(0, 5, 1), day.addingTimeInterval(60)), release(V(0, 5, 0), day)])[0]
        #expect(model.days(sameDay) == first)
        #expect(model.days(PatchNotes.series([release(V(0, 5, 0), nil)])[0]) == nil)
    }

    @Test func searchingOpensEveryMatch() async throws {
        let model = try makeModel(current: V(0, 3, 0))
        await model.load()
        model.query = "창"
        guard case .series(let shown) = model.state else { Issue.record("\(model.state)"); return }
        #expect(shown.map(\.name) == ["0.2"])
        #expect(shown[0].releases.map(\.version) == [V(0, 2, 0)])
        #expect(model.isOpen(shown[0]))

        model.kind = .fix
        #expect(model.state == .noMatch)
        #expect(model.noMatch == "‘창’에 맞는 항목 없음 (fix)")
    }

    @Test func narrowPutsTheKindsUnderTheSearch() throws {
        let model = try makeModel()
        #expect(model.narrow)
        model.width = 390 - 64
        #expect(model.narrow)
        for width: CGFloat in [720 - 64, 760] {
            model.width = width
            #expect(!model.narrow, "\(width)")
        }
    }

    @Test func everyKindHasItsOwnTone() {
        let tones = PatchNotes.Kind.allCases.map(\.tone)
        #expect(Set(tones.map { "\($0)" }).count == tones.count)
        #expect(!tones.contains(.plain) && !tones.contains(.accent))
    }

    @Test func offlineSaysSoAndRetries() async throws {
        let model = try makeModel(fails: true)
        await model.load()
        #expect(model.state == .unavailable)
    }
}
