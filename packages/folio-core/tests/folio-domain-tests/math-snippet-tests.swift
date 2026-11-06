import FolioDomain
import Foundation
import Testing

struct MathSnippetTests {
    @Test func settingsWithoutSnippetsUseTheDefaults() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"dayBoundaryMinutes": 240}"#.utf8))
        #expect(s.mathSnippets == nil && s.snippets == MathSnippet.defaults)
    }

    @Test func changedSnippetsRoundTrip() throws {
        let mine = [MathSnippet(trigger: "rr", body: "\\mathbb{R}", inMath: true)]
        let data = try JSONEncoder().encode(Settings(mathSnippets: mine))
        #expect(try JSONDecoder().decode(Settings.self, from: data).snippets == mine)
    }

    /// Two snippets with one trigger in one place would leave which one Tab expands to their order.
    @Test func defaultTriggersAreDistinctWherever() {
        let keys = MathSnippet.defaults.map { "\($0.inMath) \($0.trigger)" }
        #expect(Set(keys).count == keys.count)
    }
}
