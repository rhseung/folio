import FolioDomain
import Testing

@testable import FolioDev

struct ReleasePlanTests {
    typealias V = PatchNotes.Version
    typealias Step = ReleasePlan.Step

    static func pr(_ number: Int, notes: Bool, labels: [String] = [], closes: [Int] = []) -> ReleasePlan.PR {
        ReleasePlan.PR(
            merged: PatchNotes.Merged(number: number, title: "pr", body: notes ? "## 패치 노트\n- fix: 칸 닫기" : "## 확인\n- 테스트"),
            labels: labels, commit: "c\(number)", closes: closes)
    }

    static func bundle(_ name: String, closed: [Int], open: [Int] = []) -> ReleasePlan.Bundle {
        ReleasePlan.Bundle(
            name: name,
            issues: closed.map { ReleasePlan.Issue(number: $0, title: "이슈 \($0)", open: false) }
                + open.map { ReleasePlan.Issue(number: $0, title: "이슈 \($0)", open: true) })
    }

    @Test func everyMergeWithPatchNotesIsItsOwnVersionAtItsCommit() {
        let prs = [Self.pr(3, notes: true), Self.pr(1, notes: false), Self.pr(2, notes: true)]
        #expect(
            ReleasePlan.steps(after: V(0, 5, 0), prs: prs) == [
                Step(version: V(0, 5, 1), commit: "c3", prs: [3]),
                Step(version: V(0, 5, 2), commit: "c2", prs: [1, 2]),
            ])
    }

    @Test func mergesWithoutPatchNotesWaitForTheNextOne() {
        #expect(ReleasePlan.steps(after: V(0, 5, 0), prs: [Self.pr(1, notes: false)]).isEmpty)
        #expect(ReleasePlan.steps(after: V(0, 5, 0), prs: []).isEmpty)
        #expect(ReleasePlan.steps(after: V(0, 5, 0), prs: [Self.pr(1, notes: false, labels: [ReleasePlan.minorLabel])]).isEmpty)
        #expect(ReleasePlan.steps(after: nil, prs: [Self.pr(1, notes: true)]) == [Step(version: V(0, 1, 0), commit: "c1", prs: [1])])
    }

    @Test func theMinorLabelRaisesItsOwnOrTheNextRelease() {
        let labelled = [
            Self.pr(1, notes: true), Self.pr(2, notes: true, labels: ["area/ops", ReleasePlan.minorLabel]), Self.pr(3, notes: true),
        ]
        #expect(ReleasePlan.steps(after: V(0, 5, 7), prs: labelled).map(\.version) == [V(0, 5, 8), V(0, 6, 0), V(0, 6, 1)])
        let carried = [Self.pr(1, notes: false, labels: [ReleasePlan.minorLabel]), Self.pr(2, notes: true)]
        #expect(ReleasePlan.steps(after: V(0, 4, 0), prs: carried).map(\.version) == [V(0, 5, 0)])
    }

    @Test func thePRThatClosesABundlesLastIssueReleasesTheMinor() {
        let lms = Self.bundle("LMS 연동", closed: [10, 11, 12])
        let prs = [Self.pr(1, notes: true, closes: [10]), Self.pr(2, notes: true, closes: [12]), Self.pr(3, notes: true, closes: [99])]
        #expect(
            ReleasePlan.steps(after: V(0, 5, 3), prs: prs, bundles: [lms]) == [
                Step(version: V(0, 5, 4), commit: "c1", prs: [1]),
                Step(version: V(0, 6, 0), commit: "c2", bundles: ["LMS 연동"], prs: [2]),
                Step(version: V(0, 6, 1), commit: "c3", prs: [3]),
            ])
    }

    @Test func aBundleWithAnOpenIssueDoesNotEnd() {
        let lms = Self.bundle("LMS 연동", closed: [10], open: [11])
        let prs = [Self.pr(1, notes: true, closes: [10])]
        #expect(ReleasePlan.steps(after: V(0, 5, 0), prs: prs, bundles: [lms]).map(\.version) == [V(0, 5, 1)])
    }

    @Test func aBundleEndsOnceEvenIfItsIssuesCloseAgain() {
        let lms = Self.bundle("LMS 연동", closed: [10, 11])
        let prs = [Self.pr(1, notes: true, closes: [10, 11])]
        #expect(ReleasePlan.steps(after: V(0, 6, 2), prs: prs, bundles: [lms], released: ["LMS 연동"]).map(\.version) == [V(0, 6, 3)])
    }

    @Test func aBundleEndingWithoutNotesNamesTheNextRelease() {
        let tabs = Self.bundle("탭 끌기", closed: [20])
        let shortcuts = Self.bundle("단축키", closed: [30])
        let prs = [Self.pr(1, notes: false, closes: [20]), Self.pr(2, notes: true, closes: [30]), Self.pr(3, notes: true)]
        #expect(
            ReleasePlan.steps(after: V(0, 6, 0), prs: prs, bundles: [tabs, shortcuts]) == [
                Step(version: V(0, 7, 0), commit: "c2", bundles: ["탭 끌기", "단축키"], prs: [1, 2]),
                Step(version: V(0, 7, 1), commit: "c3", prs: [3]),
            ])
    }

    @Test func aBundleEndsAtItsLastClosingPR() {
        let lms = Self.bundle("LMS 연동", closed: [10, 11])
        #expect(ReleasePlan.ends(lms, at: 1, in: [Self.pr(1, notes: true, closes: [10]), Self.pr(2, notes: true, closes: [11])]))
        #expect(!ReleasePlan.ends(lms, at: 0, in: [Self.pr(1, notes: true, closes: [10]), Self.pr(2, notes: true, closes: [11])]))
        #expect(!ReleasePlan.ends(Self.bundle("빈 묶음", closed: []), at: 0, in: [Self.pr(1, notes: true)]))
    }

    @Test func aBundleClosedByHandAfterItsLastPRShippedEndsAtTheNextRelease() {
        let lms = Self.bundle("LMS 연동", closed: [10, 11])
        let prs = [Self.pr(1, notes: false), Self.pr(2, notes: true), Self.pr(3, notes: true)]
        #expect(
            ReleasePlan.steps(after: V(0, 5, 3), prs: prs, bundles: [lms]) == [
                Step(version: V(0, 6, 0), commit: "c2", bundles: ["LMS 연동"], prs: [1, 2]),
                Step(version: V(0, 6, 1), commit: "c3", prs: [3]),
            ])
        #expect(
            ReleasePlan.steps(after: V(0, 6, 1), prs: [Self.pr(4, notes: true)], bundles: [lms], released: ["LMS 연동"]) == [
                Step(version: V(0, 6, 2), commit: "c4", prs: [4])
            ])
    }

    @Test func unpublishedTagsComeFirstInOrder() {
        let tags = [V(0, 6, 0), V(0, 5, 0), V(0, 5, 1)]
        #expect(ReleasePlan.pending(tags: tags, published: [V(0, 5, 0)]) == [V(0, 5, 1), V(0, 6, 0)])
        #expect(ReleasePlan.pending(tags: tags, published: Set(tags)).isEmpty)
    }

    @Test func thePreviousTagIsByVersionSoTwoTagsOnACommitWork() {
        let tags = [V(0, 1, 0), V(0, 5, 4), V(0, 6, 0), V(0, 2, 0)]
        #expect(ReleasePlan.previous(before: V(0, 6, 0), among: tags) == V(0, 5, 4))
        #expect(ReleasePlan.previous(before: V(0, 3, 0), among: tags) == V(0, 2, 0))
        #expect(ReleasePlan.previous(before: V(0, 1, 0), among: tags) == nil)
    }

    @Test func aBundleIsTheLabelAfterItsPrefix() {
        #expect(ReleasePlan.bundleName(ofLabel: "bundle/LMS 연동") == "LMS 연동")
        #expect(ReleasePlan.bundleName(ofLabel: "bundle/") == nil)
        #expect(ReleasePlan.bundleName(ofLabel: "area/ops") == nil)
    }

    @Test func theSummaryListsWhatIsLeftInEachBundle() {
        let summary = ReleasePlan.summary(
            [Self.bundle("탭 끌기", closed: [20], open: [22, 21]), Self.bundle("LMS 연동", closed: [10]), Self.bundle("끝남", closed: [1])],
            released: ["끝남"])
        #expect(summary.contains("### 탭 끌기\n이슈 3개 중 2개가 남았습니다.\n- #21 이슈 21\n- #22 이슈 22\n"))
        #expect(summary.contains("### LMS 연동\n이슈 1개가 모두 닫혔고"))
        #expect(!summary.contains("끝남"))
        #expect(ReleasePlan.summary([], released: []).contains("열린 묶음이 없습니다"))
    }

    @Test func theTagMessageKeepsTheBundles() {
        #expect(ReleaseTags.bundles(inMessage: "Folio 0.6.0\n\nBundle: LMS 연동\nBundle: 단축키\n") == ["LMS 연동", "단축키"])
        #expect(ReleaseTags.bundles(inMessage: "Folio 0.5.1").isEmpty)
    }

    @Test func aDropRangeCanReachTheEndOfAMinor() throws {
        let tags = [V(0, 1, 0), V(0, 1, 1), V(0, 1, 8), V(0, 1, 9), V(0, 1, 10), V(0, 2, 0)]
        #expect(try ReleaseCommand.Renumber.range("0.1.1-0.1.x", among: tags) == [V(0, 1, 1), V(0, 1, 8), V(0, 1, 9), V(0, 1, 10)])
        #expect(try ReleaseCommand.Renumber.range("0.1.1-0.1.8", among: tags) == [V(0, 1, 1), V(0, 1, 8)])
        #expect(try ReleaseCommand.Renumber.range("0.1.9", among: tags) == [V(0, 1, 9)])
        #expect(throws: DevError.self) { try ReleaseCommand.Renumber.range("0.1.x", among: tags) }
    }

    @Test func theTableShowsEachVersionsPRApartFromTheQuietOnes() {
        let steps = [
            Step(version: V(0, 5, 1), commit: "c1", prs: [544]),
            Step(version: V(0, 6, 0), commit: "c3", bundles: ["LMS 연동"], prs: [550, 552, 554]),
        ]
        let table = ReleaseCommand.table(pending: [], steps: steps)
        #expect(table.contains("| 0.5.1 | #544 |  |  |"))
        #expect(table.contains("| 0.6.0 | #554 | #550 #552 | LMS 연동 |"))
    }
}
