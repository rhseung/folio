import FolioAI
import FolioDomain
import Foundation
import Testing

struct LectureSectionTests {
    @Test func claudesSectionsTakeUnitsByExactTitleOnly() async throws {
        let device = UUID(), now = Date()
        let units = ["매칭", "Hall의 결혼 정리"].enumerated().map { FolioDomain.Unit(device: device, at: now, title: $1, order: $0 + 1) }
        let reply = #"{"sections":[{"title":"Hall","firstPage":9,"unit":"Hall의 결혼 정리"},{"title":"Matchings","firstPage":2,"unit":"매칭"},{"title":"Berge","firstPage":14,"unit":"Berge 정리"}]}"#
        let fake = FakeProvider(responses: [FakeProvider.reply(reply)])
        let titles: [String?] = (1...20).map { $0 % 3 == 0 ? nil : "p\($0)" }
        let split = try #require(try await ClaudeClient(provider: fake).lectureSections(file: "05_Matchings.pdf", pageTitles: titles, units: units))
        #expect(split.sections.map(\.pages) == [1...8, 9...13, 14...20])
        #expect(split.sections[0].unit == units[0].id && split.sections[0].match == .claude)
        #expect(split.sections[1].unit == units[1].id)
        // A unit the course doesn't have is a new one, never a made-up match.
        #expect(split.sections[2].isNew && split.sections[2].title == "Berge")

        let request = try #require(await fake.requests.first)
        #expect(request.model == TaskConfig.small && request.output_config?.format?.schema == LectureSectionDrafts.schema)
        guard case .text(let text, _)? = request.messages.first?.content.first else { Issue.record("text"); return }
        #expect(text.contains("- Hall의 결혼 정리") && text.contains("3: \n") && text.contains("20: p20"))
    }
}
