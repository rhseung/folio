import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import SwiftUI
import Testing
@testable import Folio

@MainActor
struct SessionMenuModelTests {
    /// A class the timetable holds weeks ahead of the semester's start, not saved yet.
    func planned(_ workspace: Workspace) throws -> Workspace.SuggestedSession {
        workspace.run(CourseSet(course: graphTheory, [.schedule([ClassTime(weekday: 2, startMinute: 10 * 60 + 30, endMinute: 11 * 60 + 45)])]))
        let course = try #require(workspace.course(graphTheory))
        let semester = try #require(workspace.semester(of: course.file.course))
        let now = try #require(semester.start?.date(in: workspace.calendar)).addingTimeInterval(7 * 86_400)
        return try #require(workspace.plannedSessions(for: course, now: now).dropFirst().first)
    }

    func file(_ workspace: Workspace) throws -> CourseFile { try #require(workspace.course(graphTheory)).file }

    @Test func markingAPlannedClassAbsentSavesTheSessionWithIt() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionMenuModel(workspace: workspace, courseId: graphTheory)
        let item = try planned(workspace)
        #expect(model.canMark(item, .absent))
        let s = try #require(model.make(item, attendance: .absent))
        #expect(s.date == item.suggestion.date && s.week == item.draft.week)
        #expect(model.attendance(of: s) == .absent)
        #expect(try file(workspace).attendance.filter { $0.sessionId == s.id }.count == 1)
    }

    @Test func aPlannedClassesRoughNoteMakesTheSessionFirst() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionMenuModel(workspace: workspace, courseId: graphTheory)
        let item = try planned(workspace)
        let note = try #require(model.roughNote(item))
        let s = try #require(try file(workspace).sessions.first { $0.date == item.suggestion.date })
        #expect(s.roughNoteId == note)
    }

    // MARK: A saved class's menu (#403)

    func source(_ workspace: Workspace, _ id: UUID, host: MenuHost = .elsewhere, sheets: ItemSheetsAction = ItemSheetsAction()) throws -> SessionMenuSource {
        let session = try #require(try file(workspace).sessions.first { $0.id == id })
        return SessionMenuSource(workspace: workspace, courseId: graphTheory, session: session, host: host, now: workspace.now, openNote: { _ in },
                                 openLink: OpenLinkAction(), openURL: OpenURLAction { _ in .handled }, sheets: sheets)
    }

    func perform(_ row: MenuRow) {
        switch row.kind {
        case .action(let action): action()
        case .check(let on, let set): set(!on)
        case .submenu, .share: break
        }
    }

    func row(_ source: SessionMenuSource, _ title: LocalizedStringResource) throws -> MenuRow {
        try #require(source.commands.map(source.row).first { $0.title == String(localized: title) })
    }

    /// After the class: its review note to make and the one check, then editing, sharing and deleting. Off its own
    /// screen, opening it leads.
    @Test func afterClassTheMenuOffersTheReviewAndItsCheck() throws {
        let workspace = try fixtureWorkspace()
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: workspace.now.addingTimeInterval(-86_400)))?.made)
        let menu = try source(workspace, id)
        #expect(menu.commands == [.open, .makeReviewNote, .review(.needed), .edit, .share, .remove])
        #expect(menu.commands.map(menu.row).map(\.title) == ["열기", "복습 노트 만들기", "복습 필요 없음", "편집…", "공유", "삭제…"])
        #expect(try source(workspace, id, host: .own).commands.first == .makeReviewNote)

        perform(try row(menu, .sessionsSkipsReview))
        #expect(try source(workspace, id).commands.contains(.review(.notNeeded)))
        #expect(try file(workspace).sessions.first { $0.id == id }?.skipsReview == true)

        // Made, the note is opened from here on, and the check becomes 작성 완료.
        perform(try row(menu, .sessionsMakeReviewNote))
        let written = try source(workspace, id)
        #expect(written.commands.contains(.openNote(.review)) && written.commands.contains(.review(.writing)))
        perform(try row(written, .sessionsReviewWritten))
        #expect(try file(workspace).sessions.first { $0.id == id }?.reviewNoteUnfinished == false)
    }

    /// Ahead of the class: recording, and no review yet.
    @Test func aheadOfClassTheMenuOffersRecording() throws {
        let workspace = try fixtureWorkspace()
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: workspace.now.addingTimeInterval(2 * 86_400)))?.made)
        let menu = try source(workspace, id, host: .own)
        #expect(menu.commands == [.record, .edit, .share, .remove])
    }

    /// Editing and deleting go to the window, so any place that shows the class can do them.
    @Test func editAndDeleteAskTheWindow() throws {
        let workspace = try fixtureWorkspace()
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: workspace.now.addingTimeInterval(-86_400)))?.made)
        var presented: ItemSheet?
        var asked: PendingAction?
        let menu = try source(workspace, id, sheets: ItemSheetsAction(present: { presented = $0 }, confirm: { asked = $0 }))
        perform(try row(menu, .commonEditEllipsis))
        guard case .session(let request)? = presented else { Issue.record("no sheet"); return }
        #expect(request.session == id && request.course == graphTheory && !request.asked)
        perform(try row(menu, .commonDeleteEllipsis))
        #expect(asked != nil && asked?.refusal == nil)
        asked?.perform()
        #expect(try file(workspace).sessions.allSatisfy { $0.id != id })
    }

    /// On a unit's page the class can be let go of that unit.
    @Test func aUnitPageUnlinksTheClass() throws {
        let workspace = try fixtureWorkspace()
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: workspace.now.addingTimeInterval(-86_400)))?.made)
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        workspace.run(UnitLink(course: graphTheory, unit: unit, sessions: [id], linked: true))
        let menu = try source(workspace, id, host: .unit(unit))
        #expect(menu.commands.contains(.unlink(unit: unit)))
        perform(try row(menu, .unitsUnlinkSession))
        #expect(try file(workspace).sessions.first { $0.id == id }?.unitIds.isEmpty == true)
    }

    /// One skip for every screen: the review screen's keeps the time the unit was open, a list's has none.
    @Test func skippingFromTheReviewScreenKeepsTheTimeOpen() throws {
        let workspace = try fixtureWorkspace()
        let a = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let b = try #require(workspace.run(UnitAdd(course: graphTheory, title: "채색"))?.made)
        let review = ReviewModel(workspace: workspace, items: [.init(courseId: graphTheory, unitId: a)])
        review.started = .now.addingTimeInterval(-120)
        review.record(.skip)
        _ = workspace.skipReviews([(graphTheory, b)])

        let events = workspace.reviews(of: graphTheory).map(\.event)
        #expect(events.map(\.result) == [.skip, .skip])
        #expect(events.first { $0.unitId == a }.map { $0.seconds >= 120 } == true)
        #expect(events.first { $0.unitId == b }?.seconds == 0)
        let log = try #require(workspace.course(graphTheory)).store.log
        #expect(try log.readAll().events(StudySessionEvent.self).map(\.event.screen) == ["review"])
    }
}
