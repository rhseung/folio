import FolioActions
import FolioDomain
import FolioMarkdown
import Foundation
import Testing

@testable import Folio

@MainActor
struct NavigatorTests {
    @Test func movesBackAndForwardThroughWhereTheWindowWas() {
        let navigator = Navigator()
        let course = Navigator.Entry(link: .course(graphTheory), course: graphTheory)
        let grades = Navigator.Entry(link: .place(.grades))
        navigator.go(course)
        navigator.go(grades)
        #expect(navigator.screen == .grades)
        #expect(navigator.backList.map(\.link) == [.course(graphTheory), .place(.today)])
        navigator.back(2)
        #expect(navigator.screen == .today)
        #expect(navigator.forwardList.map(\.link) == [.course(graphTheory), .place(.grades)])
        navigator.forward()
        #expect(navigator.screen == .course(graphTheory))
        navigator.go(Navigator.Entry(link: .place(.people)))
        #expect(navigator.forwardList.isEmpty)
    }

    @Test func anotherPageOfTheSameFileIsTheSameStep() {
        let navigator = Navigator()
        let file = AppLink(.material, UUID())
        navigator.go(Navigator.Entry(link: file.with(.page(3)), course: graphTheory))
        navigator.go(Navigator.Entry(link: file.with(.page(12)), course: graphTheory))
        #expect(navigator.current.link == file.with(.page(12)))
        #expect(navigator.backList.count == 1)
        #expect(navigator.screen == .course(graphTheory))
    }

    @Test func anotherMomentOfTheSameRecordingIsTheSameStep() {
        let navigator = Navigator()
        let replay = AppLink(.recording, UUID())
        navigator.go(Navigator.Entry(link: replay, course: graphTheory))
        for t in stride(from: 5, through: 60, by: 5) { navigator.go(Navigator.Entry(link: replay.with(.time(t)), course: graphTheory)) }
        #expect(navigator.current.link == replay.with(.time(60)))
        #expect(navigator.backList.count == 1)
    }

    @Test func aLinkFromOutsideOpensInANewTabUnlessTheWindowWasMadeForIt() {
        let fresh = Navigator()
        #expect(fresh.outsidePlacement(windowAge: 0.3) == .here)
        #expect(fresh.outsidePlacement(windowAge: Navigator.freshWindow + 1) == .tab)
        let moved = Navigator()
        moved.go(Navigator.Entry(link: .place(.grades)))
        moved.back()
        #expect(moved.outsidePlacement(windowAge: 0.3) == .tab)
        let linked = Navigator(Navigator.Entry(link: .course(graphTheory), course: graphTheory))
        #expect(linked.outsidePlacement(windowAge: 0.3) == .tab)
    }

    @Test func eachSettingsTabIsAStep() {
        let navigator = Navigator()
        navigator.go(Navigator.Entry(link: .settings(.general)))
        navigator.go(Navigator.Entry(link: .settings(.claude)))
        #expect(navigator.screen == .settings)
        navigator.back()
        #expect(navigator.current.link == .settings(.general))
    }

    @Test func aPersonOpensOnThePeoplePage() {
        let navigator = Navigator(Navigator.Entry(link: AppLink(.person, UUID())))
        #expect(navigator.screen == .people)
    }
}

@MainActor
struct WorkspaceLinkTests {
    @Test func findsTheCourseThatHoldsWhatALinkNames() throws {
        let workspace = try fixtureWorkspace()
        let exam = try #require(workspace.run(ExamAdd(course: graphTheory, title: "중간고사"))?.made)
        #expect(workspace.entry(for: AppLink(.exam, exam))?.course == graphTheory)
        #expect(workspace.entry(for: .course(graphTheory, page: .units))?.course == graphTheory)
        #expect(workspace.entry(for: .place(.grades)) == Navigator.Entry(link: .place(.grades)))
        #expect(workspace.entry(for: AppLink(.exam, UUID())) == nil)
        #expect(workspace.entry(for: AppLink(.semester, UUID())) == nil)
    }

    @Test func aCardIsFoundInItsUnitsQuiz() throws {
        let workspace = try fixtureWorkspace()
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let card = QuizCard(device: workspace.device, at: .now, unitId: unit, type: .free, category: .definition, prompt: "p", answer: "a")
        workspace.run(QuizCardSave(course: graphTheory, cards: [card]))
        #expect(workspace.entry(for: AppLink(.card, card.id))?.course == graphTheory)
        #expect(workspace.entry(for: AppLink(.card, UUID())) == nil)
    }

    @Test func eachStepHasAName() throws {
        let workspace = try fixtureWorkspace()
        let exam = try #require(workspace.run(ExamAdd(course: graphTheory, title: "중간고사"))?.made)
        let title = workspace.title(of: Navigator.Entry(link: AppLink(.exam, exam), course: graphTheory))
        #expect(title.hasSuffix("· 중간고사"))
        #expect(workspace.title(of: Navigator.Entry(link: .place(.today))) == String(localized: .rootNavToday))

        let session = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now))?.made)
        let recording = Recording(device: workspace.device, at: .now, sessionId: session, file: "Recordings/a.m4a")
        try ActionContext(gist: try #require(workspace.gist), device: workspace.device).edit(graphTheory) { $0.recordings = [recording] }
        workspace.reload()
        let day = try #require(workspace.course(graphTheory)?.file).day(
            of: try #require(workspace.course(graphTheory)?.file.sessions.first { $0.id == session }), calendar: workspace.calendar)
        let replay = Navigator.Entry(link: AppLink(.recording, recording.id, anchor: .time(90)), course: graphTheory)
        #expect(workspace.title(of: replay).hasSuffix("· " + String(localized: .recordingPageNamed(day))))
        #expect(workspace.entry(for: AppLink(.recording, recording.id))?.course == graphTheory)
        #expect(workspace.title(of: Navigator.Entry(link: .settings(.claude))) == "\(String(localized: .rootNavSettings)) · Claude")
    }

    @Test func aLinkIsNamedWithItsPage() throws {
        let workspace = try fixtureWorkspace()
        workspace.run(MaterialTrack(course: graphTheory))
        let course = try #require(workspace.course(graphTheory))
        let material = try #require(course.file.materials.first)
        let file = (material.path as NSString).lastPathComponent
        let page = AppLink(.material, material.id, anchor: .page(2))
        #expect(workspace.name(of: page) == file)
        #expect(workspace.label(of: page) == "\(file) › \(String(localized: .notesAssistLinkPage(2)))")
        #expect(workspace.label(of: .settings(.claude)) == "\(String(localized: .rootNavSettings)) · Claude")
        #expect(workspace.name(of: .course(graphTheory, page: .units))?.hasPrefix(course.title) == true)
        #expect(workspace.name(of: AppLink(.exam, UUID())) == nil)

        let embeds = NoteEmbedSource(workspace: workspace, course: course, own: nil).embeds(revision: 0, text: "")
        for written in ["[[\(page.string)]]", "[[material:\(material.id.uuidString)#page=2]]"] {
            let html = HTMLRenderer.blocks(ParsedNote(written), embeds: embeds).map(\.html).joined()
            #expect(html.contains(">\(file) › \(String(localized: .notesAssistLinkPage(2)))</a>"), "\(html)")
        }
    }

    @Test func aPastedAddressBecomesALinkToWhatItNames() {
        let id = UUID()
        let named = { (link: AppLink) -> String? in link.kind == .material ? "05_Matchings.pdf" : nil }
        let page = AppLink(.material, id, anchor: .page(2))
        #expect(pastedNoteLink(page.string, into: "앞 ", at: 2, name: named) == "[[material:\(id.uuidString)#page=2|05_Matchings.pdf]]")
        #expect(
            pastedNoteLink(" \(AppLink(.note, id, anchor: .block("c1")).string)\n", into: "", at: 0, name: named)
                == "[[note:\(id.uuidString)#^c1]]")
        #expect(
            pastedNoteLink(AppLink(.recording, id, anchor: .time(750)).string, into: "", at: 0, name: named)
                == "[[recording:\(id.uuidString)#t=12:30]]")
        #expect(
            pastedNoteLink(AppLink.course(id, page: .units).string, into: "", at: 0, name: { _ in "그래프 이론 · 단원" })
                == "[[folio://course/\(id.uuidString)/units|그래프 이론 · 단원]]")
        #expect(pastedNoteLink(AppLink.settings(.claude).string, into: "", at: 0, name: { _ in nil }) == "[[folio://settings/claude]]")
        let odd = AppLink(.note, id, anchor: .heading("A|B"))
        #expect(pastedNoteLink(odd.string, into: "", at: 0, name: { _ in nil }) == "[[\(odd.string)]]")
        #expect(pastedNoteLink(page.string, into: "[[]]", at: 2, name: named) == nil)
        #expect(pastedNoteLink(page.string, into: "`a`", at: 2, name: named) == nil)
        #expect(pastedNoteLink("folio://nowhere", into: "", at: 0, name: named) == nil)
        #expect(pastedNoteLink("https://example.com", into: "", at: 0, name: named) == nil)
    }

    @Test func aSettingsLinkWithoutATabOpensTheOneLastPicked() throws {
        let workspace = try fixtureWorkspace()
        // 테스트 호스트가 앱의 defaults를 함께 쓰므로, 사용자가 마지막으로 고른 탭을 되돌려 놓는다.
        let saved = UserDefaults.standard.string(forKey: SettingsTab.storageKey)
        defer { UserDefaults.standard.set(saved, forKey: SettingsTab.storageKey) }
        UserDefaults.standard.set(SettingsTab.backup.rawValue, forKey: SettingsTab.storageKey)
        #expect(workspace.entry(for: .place(.settings))?.link == .settings(.backup))
        #expect(workspace.entry(for: .settings(.claude))?.link == .settings(.claude))
    }
}

struct CoursePageLinkTests {
    @Test func everySectionRoundTripsThroughItsPage() {
        for section in CourseSection.allCases {
            #expect(CourseSection(section.page) == section)
        }
        for tab in SettingsTab.allCases {
            #expect(SettingsTab(tab.page) == tab)
        }
        #expect(Set(SettingsTab.allCases.map(\.page)).count == AppLink.SettingsPage.allCases.count)
    }
}

@MainActor
struct ClaudePanelLinkTests {
    final class Opened {
        var links: [AppLink] = []
        var titles: [String] = []
        var actions: [URL] = []
    }

    func coordinator(_ opened: Opened) -> HTMLView.Coordinator {
        let c = HTMLView.Coordinator()
        c.openLink = OpenLinkAction { link, _, _ in opened.links.append(link) }
        c.openNote = { opened.titles.append($0) }
        c.onAction = { opened.actions.append($0) }
        return c
    }

    @Test func anAnswersLinksOpenWhereANotesWould() throws {
        let opened = Opened()
        let c = coordinator(opened)
        let exam = AppLink(.exam, UUID()), block = AppLink(.note, UUID(), anchor: .block("proof"))
        c.open(exam.url)
        c.open(block.url)
        c.open(try #require(URL(string: "folio://note/%EB%A7%A4%EC%B9%AD%20%EC%A0%95%EB%A6%AC")))
        #expect(opened.links == [exam, block])
        #expect(opened.titles == ["매칭 정리"])
        #expect(opened.actions.isEmpty)
    }

    @Test func theButtonsStayWithThePanel() throws {
        let opened = Opened()
        let c = coordinator(opened)
        let button = try #require(URL(string: "folio://action/copy/\(UUID().uuidString)"))
        c.open(button)
        #expect(opened.actions == [button])
        #expect(opened.links.isEmpty && opened.titles.isEmpty)
    }
}
