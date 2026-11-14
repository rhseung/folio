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

    @Test func defaultTriggersAreDistinctWherever() {
        let keys = MathSnippet.defaults.map { "\($0.inMath) \($0.trigger)" }
        #expect(Set(keys).count == keys.count)
        let ascii = MathSnippet.asciiMathDefaults.map(\.trigger)
        #expect(Set(ascii).count == ascii.count)
    }

    @Test func asciiMathSnippetsAreKeptApart() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"mathSnippets": []}"#.utf8))
        #expect(s.asciiMathSnippets == nil && s.asciiSnippets == MathSnippet.asciiMathDefaults)
        #expect(MathSnippet.asciiMathDefaults.allSatisfy { $0.inMath })
        let mine = [MathSnippet(trigger: "rr", body: "RR", inMath: true)]
        let data = try JSONEncoder().encode(Settings(asciiMathSnippets: mine))
        let back = try JSONDecoder().decode(Settings.self, from: data)
        #expect(back.asciiSnippets == mine && back.snippets == MathSnippet.defaults)
    }
}
