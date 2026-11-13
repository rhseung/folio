import FolioDomain
import Testing

struct VersionTests {
    // scripts/version.sh reads and bumps exactly this shape; a suffix like -beta would be lost on the next bump.
    @Test func marketingIsMajorMinorPatch() {
        #expect(FolioVersion.marketing.wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+/) != nil)
    }
}
