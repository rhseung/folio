import Foundation
import Testing

@testable import FolioMarkdown

struct CalloutScanTests {
    @Test func theoremLikeCalloutsAreProvable() {
        for kind in ["theorem", "lemma", "corollary", "proposition", "Theorem"] {
            #expect(CalloutScan.hasProvable("# 매칭\n\n> [!\(kind)] Hall\n> 조건을 만족하면 완전 매칭이 있다.\n"))
        }
    }

    @Test func otherCalloutsAndPlainQuotesAreNot() {
        #expect(!CalloutScan.hasProvable("> [!definition] 매칭\n> 공통 끝점이 없는 변의 집합\n\n> [!proof]\n> 귀납법\n"))
        #expect(!CalloutScan.hasProvable("> 인용한 글\n> [!theorem] 인용의 첫 줄이 아니다\n"))
        #expect(!CalloutScan.hasProvable("본문에 적은 [!theorem] 표기\n"))
    }

    @Test func aFencedExampleIsNotACallout() {
        #expect(!CalloutScan.hasProvable("```markdown\n> [!theorem] 예시\n> 본문\n```\n"))
        #expect(CalloutScan.hasProvable("```markdown\n> [!note] 예시\n```\n\n> [!lemma] 실제 보조정리\n> 본문\n"))
    }

    @Test func calloutsInsideListsAndAfterFrontmatterCount() {
        #expect(CalloutScan.hasProvable("---\nkind: topic\n---\n- 항목\n\n  > [!corollary]\n  > 따름정리\n"))
    }

    @Test func kindsAddedInSettingsFollowTheirProvableFlag() {
        let table = CalloutTable(adding: [CalloutKind("claim", .theorem, provable: true), CalloutKind("theorem", .theorem)])
        #expect(CalloutScan.hasProvable("> [!claim]\n> 주장\n", callouts: table))
        #expect(!CalloutScan.hasProvable("> [!theorem]\n> 정리\n", callouts: table))
    }
}
