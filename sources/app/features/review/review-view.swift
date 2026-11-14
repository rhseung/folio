import FolioDomain
import FolioStorage
import SwiftUI

struct ReviewView: View {
    typealias Item = ReviewModel.Item
    typealias Source = ReviewModel.Source

    @State private var model: ReviewModel
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace, courseId: UUID, unitId: UUID) {
        self.init(workspace: workspace, courses: [Item(courseId: courseId, unitId: unitId)])
    }
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
                            ContentUnavailableView(
                                String(localized: .reviewNoNotes), systemImage: "doc.text",
                                description: Text(.reviewNoNotesDetail)
                            )
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
            .courseAccent(accent)
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
                        CourseMark(icon: course.file.course.icon, color: accent.color, inline: true)
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
            if model.sources.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(model.sources) { source in
                            let on = model.isShown(source)
                            Button {
                                model.pick(source)
                            } label: {
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
                .overflowFade(.horizontal)
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
    }

    func pane(_ source: Source, course: LoadedCourse, closable: Bool) -> some View {
        VStack(spacing: 0) {
            if closable {
                HStack(spacing: Theme.Space.s) {
                    Label(source.title, systemImage: source.symbol).font(Theme.Typeface.caption).foregroundStyle(
                        Theme.Palette.textSecondary
                    ).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    Button {
                        model.side = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.ghost).tint(Theme.Palette.textTertiary).help(Text(.commonClose))
                }
                .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                Theme.Palette.lineSoft.frame(height: 1)
            }
            // PDF 뷰는 처음 받은 문서를 계속 쓰고 다른 파일에는 새 뷰가 필요하므로, source를 키로 쓴다.
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
                Button {
                    finish(result)
                } label: {
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
                    .background(
                        result == .again ? Theme.Palette.dangerFill : Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.control)
                    )
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
    @State private var page: Int?

    init(model: ReviewModel, source: ReviewView.Source, note: NoteFile?, course: LoadedCourse) {
        self.model = model
        self.source = source
        self.note = note
        self.course = course
        _page = State(initialValue: (source.page ?? 1) - 1)
    }

    var body: some View {
        Group {
            switch source.id {
            case .note:
                if let note {
                    FileView(workspace: model.workspace, course: course, note: note)
                } else {
                    ContentUnavailableView(
                        String(localized: .reviewSourceFailed), systemImage: "doc.questionmark", description: Text(source.title))
                }
            case .lecture(let id):
                FileView(workspace: model.workspace, course: course, material: id, requestedPage: $page, remembersPage: false)
            }
        }
        // 시트 뒤에 있는 창의 위치 표시는 자기 걸음을 유지하고, 그 Claude 패널은 시트 뒤에 열리게 된다.
        .environment(nil as CrumbTrail?)
        .environment(\.askClaude, nil)
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
