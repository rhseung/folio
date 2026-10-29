import Algorithms
import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import Observation
import PDFKit

@MainActor @Observable
final class ReviewModel {
    struct Item {
        let courseId: UUID
        let unitId: UUID
    }

    struct Source: Identifiable {
        enum Kind: Hashable { case note(URL), lecture(UUID) }
        let id: Kind
        let title: String
        let symbol: String
        /// Rough notes and lectures are references: they open beside the review note instead of replacing it.
        let beside: Bool
        var page: Int?
    }

    let workspace: Workspace
    let items: [Item]
    var position = 0
    var started = Date.now
    var notes: [NoteFile] = []
    var sources: [Source] = []
    var main: Source.Kind?
    var side: Source.Kind?

    init(workspace: Workspace, items: [Item]) {
        self.workspace = workspace
        self.items = items
    }

    var courseId: UUID { items[position].courseId }
    var unitId: UUID { items[position].unitId }

    var current: (course: LoadedCourse, unit: FolioDomain.Unit)? {
        guard let course = workspace.course(courseId), let unit = course.file.units.first(where: { $0.id == unitId }) else { return nil }
        return (course, unit)
    }

    var isLast: Bool { position + 1 >= items.count }

    var counter: String? { items.count > 1 ? "\(position + 1) / \(items.count)" : nil }

    var mainSource: Source? { sources.first { $0.id == main } }
    var sideSource: Source? { sources.first { $0.id == side } }

    func note(for source: Source) -> NoteFile? { notes.first { .note($0.url) == source.id } }

    func sessionLine(_ course: LoadedCourse, _ unit: FolioDomain.Unit) -> String? {
        let sessions = course.file.sessions.filter { unit.sessionIds.contains($0.id) }.sorted { $0.date < $1.date }
        return sessions.isEmpty ? nil : sessions.map { course.file.name(of: $0) }.joined(separator: ", ")
    }

    func load(course: LoadedCourse, unit: FolioDomain.Unit) {
        notes = workspace.notes(for: unit, in: courseId)
        let links = course.file.sessions.filter { unit.sessionIds.contains($0.id) }.sorted { $0.date < $1.date }
            .flatMap(\.materials).uniqued(on: \.materialId)
        let lectures = links.compactMap { link in
            course.file.materials.first { $0.id == link.materialId && $0.path.lowercased().hasSuffix(".pdf") }.map { m in
                Source(id: .lecture(m.id), title: (m.path as NSString).lastPathComponent, symbol: "doc.richtext", beside: true, page: link.firstPage)
            }
        }
        sources = notes.map { n in
            Source(id: .note(n.url), title: "\(n.meta.kind.label) · \(n.title)", symbol: n.meta.kind == .rough ? "pencil.line" : "doc.text", beside: n.meta.kind == .rough)
        } + lectures
        main = (sources.first { !$0.beside } ?? sources.first)?.id
        side = nil
    }

    func isShown(_ source: Source) -> Bool { source.id == main || source.id == side }

    /// What clicking the source's chip does; nil for the note in the main pane.
    func action(for source: Source) -> String? {
        source.id == main ? nil
            : String(localized: source.id == side ? .reviewSourceCloseSide : source.beside ? .reviewSourceOpenSide : .reviewSourceSwitch)
    }

    func pick(_ source: Source) {
        if source.id == main { return }
        if source.id == side { side = nil } else if source.beside { side = source.id } else { main = source.id }
    }

    func elapsed(until date: Date) -> String {
        let s = max(0, Int(date.timeIntervalSince(started)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Under each result, the day it would set. A unit with a cycle but no next day settles with that result; one
    /// without a cycle has no day to show.
    func outcomes(now: Date) -> [ReviewResult: String] {
        let hasCycle = workspace.reviewStates(of: courseId, now: now)[unitId] != nil
        return Dictionary(uniqueKeysWithValues: Self.results.map { result in
            (result, nextReview(result: result, now: now)?.shortLabel ?? (hasCycle ? String(localized: .reviewDone) : " "))
        })
    }

    static let results: [ReviewResult] = [.again, .hard, .good, .easy]

    /// The next review day if the unit were finished now with `result`. Runs the real scheduler, so exam limits apply.
    func nextReview(result: ReviewResult, now: Date) -> LocalDate? {
        guard let course = workspace.course(courseId) else { return nil }
        let extra = [(at: now, event: ReviewEvent(unitId: unitId, result: result, seconds: 0))]
        let today = workspace.settings.studyDay(of: now, calendar: workspace.calendar)
        return workspace.reviewInputs(course, now: now, extra: extra).first { $0.unitId == unitId }
            .flatMap { ReviewScheduler.state(of: $0, settings: workspace.settings.review, today: today).due }
    }

    func record(_ result: ReviewResult) {
        workspace.run(ReviewRecord(course: courseId, unit: unitId, result: result, start: started, end: .now))
    }

    func advance() {
        position += 1
        started = .now
    }

    // MARK: Sources

    func html(of note: NoteFile, in course: LoadedCourse) -> String {
        HTMLRenderer.render(ParsedNote((try? course.store.read(note)) ?? ""))
    }

    func document(_ source: Source, in course: LoadedCourse) async -> PDFDocument? {
        guard case .lecture(let id) = source.id, let material = course.file.materials.first(where: { $0.id == id }),
              let url = try? await workspace.download(material, course: course.id) else { return nil }
        return PDFDocument(url: url)
    }
}
