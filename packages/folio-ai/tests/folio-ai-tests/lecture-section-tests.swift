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
        let pages = (1...20).map { LecturePage(title: $0 % 3 == 0 ? nil : "p\($0)") }
        let split = try #require(try await ClaudeClient(provider: fake).lectureSections(file: "05_Matchings.pdf", pages: pages, units: units))
        #expect(split.sections.map(\.pages) == [1...8, 9...13, 14...20])
        #expect(split.sections[0].unit == units[0].id && split.sections[0].match == .claude)
        #expect(split.sections[1].unit == units[1].id)
        // A unit the course doesn't have is a new one, never a made-up match.
        #expect(split.sections[2].isNew && split.sections[2].title == "Berge")

        let request = try #require(await fake.requests.first)
        #expect(request.model == TaskConfig.defaults(for: .lectureSections).model && request.output_config?.format?.schema == LectureSectionDrafts.schema)
        guard case .text(let text, _)? = request.messages.first?.content.first else { Issue.record("text"); return }
        #expect(text.contains("- Hall의 결혼 정리") && text.contains("## 3: \n") && text.contains("## 20: p20"))
    }

    /// Claude gets more than titles (#450): each page's text under its title, and a picture of a page with no words.
    @Test func theQuestionCarriesEachPagesTextAndPicturesOfTheBareOnes() async throws {
        let picture = Data([0xFF, 0xD8, 0xFF])
        let pages = [
            LecturePage(title: "Network layer", body: "Network layer\nOverview of the  data plane\nand control plane"),
            LecturePage(title: nil, body: "", image: picture),
            LecturePage(title: "IP addressing", body: "IP addressing CIDR subnets"),
        ]
        let fake = FakeProvider(responses: [FakeProvider.reply(#"{"sections":[{"title":"Overview","firstPage":1,"unit":null},{"title":"IP","firstPage":3,"unit":null}]}"#)])
        let split = try #require(try await ClaudeClient(provider: fake).lectureSections(file: "Chapter_4.pdf", pages: pages, units: []))
        #expect(split.sections.map(\.pages) == [1...2, 3...3])

        let content = try #require(await fake.requests.first?.messages.first?.content)
        guard case .text(let text, _) = content[0] else { Issue.record("text first"); return }
        // The title isn't said twice, and the body's whitespace runs together.
        #expect(text.contains("## 1: Network layer\nOverview of the data plane and control plane"))
        #expect(text.contains("## 2:  [picture below]") && text.contains("## 3: IP addressing\nCIDR subnets"))
        #expect(content.count == 3)
        #expect(content[1] == .text("Page 2:") && content[2] == .image(picture, mediaType: "image/jpeg"))
    }

    @Test func aLongDeckGetsLessTextPerPageAndAtMostSoManyPictures() {
        #expect(LecturePage.excerptLength(pages: 40) == LecturePage.excerpt)
        #expect(LecturePage.excerptLength(pages: 300) == LecturePage.budget / 300)
        #expect(LecturePage.excerptLength(pages: 10_000) == 60)
        let cut = LecturePage.excerpt("one two three four", title: nil, limit: 9)
        #expect(cut == "one two…")
        #expect(LecturePage.excerpt(String(repeating: "x", count: 50), title: nil, limit: 10) == String(repeating: "x", count: 10) + "…")

        #expect(LecturePage.pictured(words: [0, 40, 3, 50]) == [0, 2])
        let bare = LecturePage.pictured(words: Array(repeating: 0, count: 100))
        #expect(bare.count == LecturePage.maxImages && bare.first == 0 && bare.last! > 90)
        #expect(Set(bare).count == bare.count)
    }
}
