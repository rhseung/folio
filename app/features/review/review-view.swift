import FolioDomain
import FolioStorage
import PDFKit
import SwiftUI

struct ReviewOpener<Label: View>: View {
    @Environment(Workspace.self) private var workspace
    let courseId: UUID
    let unitId: UUID
    /// Units to slide in after this one, as in Today's queue.
    var then: [ReviewView.Item] = []
    @ViewBuilder var label: Label
    @State private var open = false

    var body: some View {
        Button { open = true } label: { label.contentShape(.rect) }
            .buttonStyle(.pointing(.plain))
            .sheet(isPresented: $open) { ReviewView(workspace: workspace, courses: [.init(courseId: courseId, unitId: unitId)] + then) }
    }
}

struct ReviewView: View {
    typealias Item = ReviewModel.Item
    typealias Source = ReviewModel.Source

    @State private var model: ReviewModel
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace, courseId: UUID, unitId: UUID) { self.init(workspace: workspace, courses: [Item(courseId: courseId, unitId: unitId)]) }
    init(workspace: Workspace, courses: [Item]) { _model = State(initialValue: ReviewModel(workspace: workspace, items: courses)) }

    var body: some View {
        if let current = model.current {
            let (course, unit) = current
            let accent = model.workspace.accent(model.courseId)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    header(course: course, unit: unit, accent: accent)
                    Theme.Palette.lineSoft.frame(height: 1)
                    HStack(spacing: 0) {
                        if let source = model.mainSource {
                            pane(source, course: course, closable: false)
                        } else {
                            ContentUnavailableView(String(localized: .reviewNoNotes), systemImage: "doc.text",
                                                   description: Text(.reviewNoNotesDetail))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        if let source = model.sideSource {
                            Theme.Palette.lineSoft.frame(width: 1)
                            pane(source, course: course, closable: true)
                        }
                    }
                }
                .id(model.position)
                .transition(AsymmetricTransition(insertion: .push(from: .trailing), removal: FlipAway()))
                Theme.Palette.lineSoft.frame(height: 1)
                footer()
            }
            .clipped()
            .frame(minWidth: 860, idealWidth: model.side == nil ? 960 : 1280, minHeight: 640, idealHeight: 760)
            .background(Theme.Palette.card)
            .foregroundStyle(Theme.Palette.text)
            .font(Theme.Typeface.body)
            .environment(\.accent, accent)
            .tint(accent.ink)
            .task(id: model.unitId) { model.load(course: course, unit: unit) }
        } else {
            ContentUnavailableView(String(localized: .reviewNotFound), systemImage: "questionmark.folder")
                .frame(minWidth: 480, minHeight: 320)
                .toolbar { Button(.commonClose) { dismiss() } }
        }
    }

    func header(course: LoadedCourse, unit: FolioDomain.Unit, accent: CourseAccent) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(spacing: Theme.Space.tight) {
                        CourseDot(color: accent.color, size: 8)
                        Text(.reviewCourse(course.title)).font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(accent.ink)
                    }
                    Text(unit.title).font(Theme.Typeface.columnTitle).lineLimit(2)
                    if let sessions = model.sessionLine(course, unit) {
                        Text(sessions)
                            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Space.m)
                if let counter = model.counter {
                    Text(counter).font(Theme.Typeface.caption).monospacedDigit()
                        .foregroundStyle(Theme.Palette.textTertiary).rolling("\(model.position)")
                }
                TimelineView(.periodic(from: model.started, by: 1)) { context in
                    Label(model.elapsed(until: context.date), systemImage: "timer")
                        .monospacedDigit()
                        .chip()
                }
                .help(Text(.reviewTimerHelp))
                Button(.commonClose) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            // One chip per source, so a lecture is a click away without leaving the review note.
            if model.sources.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(model.sources) { source in
                            let on = model.isShown(source)
                            Button { model.pick(source) } label: {
                                Label(source.title, systemImage: source.symbol)
                                    .font(Theme.Typeface.caption.weight(on ? .semibold : .regular))
                                    .foregroundStyle(on ? accent.ink : Theme.Palette.textSecondary)
                                    .padding(Theme.Inset.toggle)
                                    .background(on ? accent.tint : Theme.Palette.fill, in: .capsule)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.pointing(.plain))
                            .help(model.action(for: source) ?? String(localized: .reviewSourceCurrent))
                            .contextMenu { if let action = model.action(for: source) { Button(action) { model.pick(source) } } }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
    }

    func pane(_ source: Source, course: LoadedCourse, closable: Bool) -> some View {
        VStack(spacing: 0) {
            if closable {
                HStack(spacing: Theme.Space.s) {
                    Label(source.title, systemImage: source.symbol).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Button { model.side = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.ghost).tint(Theme.Palette.textTertiary).help(Text(.commonClose))
                }
                .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                Theme.Palette.lineSoft.frame(height: 1)
            }
            // Keyed by source: the PDF view keeps its first document, so another file needs a new view.
            SourcePane(model: model, source: source, note: model.note(for: source), course: course).id(source.id)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func footer() -> some View {
        let outcomes = model.outcomes(now: .now)
        return HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(.reviewQuestion).font(Theme.Typeface.bodyStrong)
                Text(.reviewQuestionDetail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
            Spacer()
            Button(.reviewSkip) { finish(.skip) }
                .buttonStyle(.ghost)
                .help(Text(.reviewSkipHelp))
            ForEach(ReviewModel.results, id: \.self) { result in
                Button { finish(result) } label: {
                    VStack(spacing: Theme.Space.xxs) {
                        HStack(spacing: Theme.Space.tight) {
                            Text("\(result.shortcut)")
                                .font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Theme.Palette.textTertiary)
                                .frame(width: 16, height: 16)
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(Theme.Palette.line))
                            Text(result.label).font(Theme.Typeface.bodyStrong)
                        }
                        Text(outcomes[result] ?? " ").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .frame(minWidth: 96)
                    .padding(.vertical, Theme.Space.s)
                    .background(result == .again ? Theme.Palette.dangerFill : Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.control))
                    .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
                .keyboardShortcut(KeyEquivalent(Character("\(result.shortcut)")), modifiers: [])
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
        .background(Theme.Palette.page)
    }

    func finish(_ result: ReviewResult) {
        model.record(result)
        guard !model.isLast else { return dismiss() }
        withAnimation(.snappy(duration: 0.45)) { model.advance() }
    }
}

private struct SourcePane: View {
    let model: ReviewModel
    let source: ReviewView.Source
    let note: NoteFile?
    let course: LoadedCourse
    @State private var html: String?
    @State private var pdf: PDFController?
    @State private var failed = false

    var body: some View {
        Group {
            if let pdf {
                PDFKitView(controller: pdf)
            } else if let html {
                HTMLView(body: html, baseURL: note?.url.deletingLastPathComponent())
            } else if failed {
                ContentUnavailableView(String(localized: .reviewSourceFailed), systemImage: "doc.questionmark", description: Text(source.title))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
    }

    func load() async {
        switch source.id {
        case .note:
            guard let note else { failed = true; return }
            html = model.html(of: note, in: course)
        case .lecture:
            guard let document = await model.document(source, in: course) else { failed = true; return }
            pdf = PDFController(document: document, page: (source.page ?? 1) - 1)
        }
    }
}

extension ReviewResult {
    var shortcut: Int {
        switch self {
        case .again: 1
        case .hard: 2
        case .good: 3
        case .easy: 4
        case .skip: 0
        }
    }
}

private struct FlipAway: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .rotation3DEffect(.degrees(phase.isIdentity ? 0 : -75), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}
