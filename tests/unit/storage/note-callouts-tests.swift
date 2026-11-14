import FolioDomain
import FolioMarkdown
import FolioStorage
import Testing

struct NoteCalloutsTests {
    @Test func settingKindsJoinTheTable() {
        var settings = Settings()
        settings.callouts = [
            NoteCallout(name: "claim", tone: "theorem", numbered: true, provable: true), NoteCallout(name: "aside", tone: "teal"),
        ]
        let table = CalloutTable(settings)
        #expect(table["claim"] == CalloutKind("claim", .theorem, numbered: true, provable: true))
        #expect(table["aside"]?.tone == .neutral)
        #expect(table.names.starts(with: CalloutKind.defaults.map(\.name)))
        #expect(CalloutTable(Settings()) == .standard)
    }

    @Test func theWritingGuideListsTheKinds() {
        var settings = Settings()
        settings.callouts = [NoteCallout(name: "claim", tone: "theorem", numbered: true)]
        #expect(NoteWritingGuide.text(for: nil).contains("definition·theorem·lemma·corollary·example·counterexample은 번호가"))
        #expect(NoteWritingGuide.text(for: settings).contains(" danger claim. "))
        #expect(NoteWritingGuide.text(for: settings).contains("counterexample·claim은 번호가"))
    }
}
