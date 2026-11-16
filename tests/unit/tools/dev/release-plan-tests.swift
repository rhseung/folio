import FolioDomain
import Testing

@testable import FolioDev

struct ReleasePlanTests {
    typealias V = PatchNotes.Version

    static func pr(_ number: Int, notes: Bool, labels: [String] = []) -> ReleasePlan.PR {
        ReleasePlan.PR(
            merged: PatchNotes.Merged(number: number, title: "pr", body: notes ? "## 패치 노트\n- fix: 칸 닫기" : "## 확인\n- 테스트"),
            labels: labels)
    }

    @Test func aMergeWithPatchNotesRaisesThePatch() {
        #expect(ReleasePlan.next(after: V(0, 5, 0), prs: [Self.pr(1, notes: true)]) == V(0, 5, 1))
        #expect(ReleasePlan.next(after: V(0, 5, 3), prs: [Self.pr(1, notes: false), Self.pr(2, notes: true)]) == V(0, 5, 4))
    }

    @Test func mergesWithoutPatchNotesAreNotReleased() {
        #expect(ReleasePlan.next(after: V(0, 5, 0), prs: [Self.pr(1, notes: false)]) == nil)
        #expect(ReleasePlan.next(after: V(0, 5, 0), prs: []) == nil)
        #expect(ReleasePlan.next(after: V(0, 5, 0), prs: [Self.pr(1, notes: false, labels: [ReleasePlan.minorLabel])]) == nil)
    }

    @Test func anApprovedMinorLabelRaisesTheMinor() {
        let prs = [Self.pr(1, notes: true), Self.pr(2, notes: false, labels: ["area/ops", ReleasePlan.minorLabel])]
        #expect(ReleasePlan.next(after: V(0, 4, 0), prs: prs) == V(0, 5, 0))
        #expect(ReleasePlan.next(after: V(0, 5, 7), prs: prs) == V(0, 6, 0))
        #expect(ReleasePlan.next(after: nil, prs: prs) == V(0, 1, 0))
    }

    @Test func anUnpublishedTagIsReleasedBeforeTheNextVersion() {
        let tags = [V(0, 5, 0), V(0, 5, 1), V(0, 6, 0)]
        let published: Set = [V(0, 5, 0), V(0, 5, 1)]
        #expect(ReleasePlan.releases(tags: tags, published: published, prs: [Self.pr(1, notes: true)]) == [V(0, 6, 0), V(0, 6, 1)])
        #expect(ReleasePlan.releases(tags: tags, published: published, prs: [Self.pr(1, notes: false)]) == [V(0, 6, 0)])
        #expect(ReleasePlan.releases(tags: tags, published: published.union([V(0, 6, 0)]), prs: []).isEmpty)
        #expect(ReleasePlan.releases(tags: [], published: [], prs: [Self.pr(1, notes: true)]) == [V(0, 1, 0)])
    }

    @Test func thePreviousTagIsByVersionSoTwoTagsOnACommitWork() {
        let tags = [V(0, 1, 0), V(0, 5, 4), V(0, 6, 0), V(0, 2, 0)]
        #expect(ReleasePlan.previous(before: V(0, 6, 0), among: tags) == V(0, 5, 4))
        #expect(ReleasePlan.previous(before: V(0, 3, 0), among: tags) == V(0, 2, 0))
        #expect(ReleasePlan.previous(before: V(0, 1, 0), among: tags) == nil)
    }
}
