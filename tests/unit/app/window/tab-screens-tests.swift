import AppKit
import FolioActions
import FolioDomain
import SwiftUI
import Testing

@testable import Folio

@MainActor @Suite(.serialized)
struct TabScreensTests {
    let workspace: Workspace
    let note: UUID
    let tabs: WindowTabs
    let window: NSWindow
    let host: NSView

    init() throws {
        workspace = try fixtureWorkspace()
        note = try #require(workspace.run(NoteAdd(course: graphTheory, title: "탭 메모", kind: .free))?.made)
        let course = try #require(workspace.course(graphTheory))
        let file = try #require(try course.store.note(id: note))
        let path = course.store.notePath(of: file.url)
        workspace.run(NoteWrite(course: graphTheory, note: path, text: (1...120).map { "줄 \($0)\n" }.joined()))
        tabs = WindowTabs(Navigator(Navigator.Entry(link: AppLink(.note, note), course: graphTheory)))
        let screens = TabScreens(tabs: tabs, workspace: workspace) { navigator in
            OpenLinkAction { link, _, course in navigator.go(Navigator.Entry(link: link, course: course)) }
        }
        .environment(workspace)
        host = NSHostingView(rootView: screens)
        window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 1200, height: 800), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
    }

    func settle(_ seconds: Double = 0.5) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(seconds))
        host.layoutSubtreeIfNeeded()
    }

    func views<T: NSView>(_ kind: T.Type) -> [T] {
        func find(_ view: NSView) -> [T] { ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap(find) }
        return find(host)
    }

    var onDisk: String {
        get throws {
            let course = try #require(workspace.course(graphTheory))
            let file = try #require(try course.store.note(id: note))
            return try course.store.readText(course.store.notePath(of: file.url))
        }
    }

    func away() async throws {
        tabs.open(Navigator(Navigator.Entry(link: .place(.grades))))
        try await settle()
        #expect(tabs.alive.count == 2)
        tabs.select(number: 1)
        try await settle()
    }

    func commandE() throws {
        let key = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: "e", charactersIgnoringModifiers: "e", isARepeat: false, keyCode: 14))
        try #require(window.performKeyEquivalent(with: key))
    }

    @Test func aKeptTabKeepsItsScroll() async throws {
        try await settle(2)
        let editor = try #require(views(NoteTextView.self).first)
        let scroll = try #require(editor.enclosingScrollView)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        scroll.reflectScrolledClipView(scroll.contentView)

        try await away()
        #expect(views(NoteTextView.self).first === editor)
        #expect(scroll.contentView.bounds.origin.y == 600)
    }

    @Test func aKeptTabIsNotLaidOutAsTheWindowResizes() async throws {
        try await settle(2)
        let editor = try #require(views(NoteTextView.self).first)
        let scroll = try #require(editor.enclosingScrollView)
        let before = scroll.frame.size
        tabs.open(Navigator(Navigator.Entry(link: .place(.grades))))
        try await settle()

        window.setContentSize(NSSize(width: 1500, height: 900))
        try await settle()
        #expect(scroll.frame.size == before)

        tabs.select(number: 1)
        try await settle()
        #expect(views(NoteTextView.self).first === editor)
        #expect(scroll.frame.width > before.width)

        window.setContentSize(NSSize(width: 1250, height: 900))
        try await settle()
        let content = try #require(window.contentView)
        #expect(scroll.convert(scroll.bounds, to: nil).maxX <= content.bounds.width)
    }

    @Test func aKeptTabKeepsItsViewMode() async throws {
        try await settle(2)
        try commandE()
        try await settle()
        #expect(views(NoteTextView.self).isEmpty)
        let preview = try #require(views(PreviewWebView.self).first)

        try await away()
        #expect(views(NoteTextView.self).isEmpty)
        #expect(views(PreviewWebView.self).first === preview)
    }

    @Test func onlyTheTabInFrontTakesTheKeys() async throws {
        try await settle(2)
        tabs.open(Navigator(Navigator.Entry(link: .place(.grades))))
        try await settle()
        let key = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: "e", charactersIgnoringModifiers: "e", isARepeat: false, keyCode: 14))
        _ = window.performKeyEquivalent(with: key)
        try await settle()

        tabs.select(number: 1)
        try await settle(1)
        let editors = views(NoteTextView.self).count
        #expect(editors == 1)
    }

    @Test func aDroppedNoteTabKeepsWhatWasTyped() async throws {
        try await settle(2)
        let editor = try #require(views(NoteTextView.self).first)
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.insertText("방금 쓴 줄", replacementRange: editor.selectedRange())
        try await settle(0.1)
        // 편집기가 저장하기 전에 기다리는 1초보다 짧은 사이에 입력했다.
        #expect(try !onDisk.contains("방금 쓴 줄"))

        tabs.open(Navigator(Navigator.Entry(link: .place(.grades))))
        try await settle(0.1)
        tabs.dropBackground()
        try await settle(0.3)
        #expect(tabs.alive == [tabs.selected])
        #expect(views(NoteTextView.self).isEmpty)
        #expect(try onDisk.contains("방금 쓴 줄"))

        tabs.select(number: 1)
        try await settle(2)
        #expect(views(NoteTextView.self).first?.string.contains("방금 쓴 줄") == true)
    }
}
