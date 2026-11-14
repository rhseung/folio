import FolioDomain
import Testing

struct VersionTests {
    // `folio-dev version`은 정확히 이 꼴을 읽고 올리므로(`PatchNotes.Version`), `-beta` 같은 꼬리는 다음에 올릴 때 사라진다.
    @Test func marketingIsMajorMinorPatch() {
        #expect(FolioVersion.marketing.wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+/) != nil)
    }
}
