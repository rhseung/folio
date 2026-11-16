import FolioDomain
import Testing

struct VersionTests {
    // `folio-dev version stamp`가 태그의 X.Y.Z(`PatchNotes.Version`)를 이 자리에 써넣는다.
    @Test func marketingIsMajorMinorPatch() {
        #expect(FolioVersion.marketing.wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+/) != nil)
    }
}
