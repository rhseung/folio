import FolioDomain
import SwiftUI

struct RecordingBar: View {
    @State private var model: RecordingBarModel
    @State private var showingTranscript = false
    let open: (AppLink) -> Void

    init(workspace: Workspace, open: @escaping (AppLink) -> Void) {
        _model = State(initialValue: RecordingBarModel(workspace: workspace))
        self.open = open
    }

    var body: some View {
        let recorder = model.recorder
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Button {
                        if let id = model.course?.id { open(.course(id)) }
                    } label: {
                        Text(model.courseTitle).font(Theme.Typeface.bodyStrong).foregroundStyle(
                            model.paused ? Theme.Palette.textSecondary : model.accent.ink
                        ).lineLimit(1)
                    }
                    .help(Text(.recordingOpenCourse))
                    if let session = model.sessionName, let link = model.sessionLink {
                        Button {
                            open(link)
                        } label: {
                            Text(session).font(Theme.Typeface.caption).foregroundStyle(
                                model.paused ? Theme.Palette.textTertiary : Theme.Palette.textSecondary
                            ).lineLimit(1)
                        }
                        .help(Text(link.kind == .note ? .recordingOpenSession : .recordingOpenSessions))
                    }
                }
                .buttonStyle(.pointing(.plain))
                Spacer(minLength: Theme.Space.xs)
                Text(RecordingTime.label(recorder.elapsed))
                    .font(Theme.Typeface.figureSmall)
                    .foregroundStyle(model.paused ? Theme.Palette.textSecondary : Theme.Palette.danger)
                    .contentTransition(.numericText())
            }
            Text(model.line)
                .font(Theme.Typeface.caption)
                .foregroundStyle(
                    model.paused ? Theme.Palette.textTertiary : recorder.volatile.isEmpty ? Theme.Palette.text : Theme.Palette.textSecondary
                )
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
            HStack(spacing: Theme.Space.m) {
                LevelMeter(level: model.recording ? recorder.level : 0)
                Spacer(minLength: 0)
                Button {
                    recorder.bookmark()
                } label: {
                    HStack(spacing: Theme.Space.xxs) {
                        Image(systemName: recorder.bookmarks.isEmpty ? "bookmark" : "bookmark.fill")
                            .symbolEffect(.bounce, value: recorder.bookmarks.count)
                            .contentTransition(.symbolEffect(.replace))
                        if !recorder.bookmarks.isEmpty {
                            Text(recorder.bookmarks.count, format: .number).font(Theme.Typeface.label).monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                }
                .help(Text(.recordingBookmarkHelp(recorder.bookmarks.count)))
                .disabled(model.settling)
                Button {
                    model.toggle()
                } label: {
                    Image(systemName: model.paused ? "record.circle" : "pause.fill").contentTransition(.symbolEffect(.replace))
                }
                .help(Text(model.paused ? .recordingResume : .recordingPause))
                .disabled(model.settling)
                Button {
                    Task { await model.stop() }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .help(Text(.recordingStop))
                .disabled(model.settling)
                Button {
                    showingTranscript.toggle()
                } label: {
                    Image(systemName: "text.quote")
                }
                .help(Text(showingTranscript ? .recordingCollapse : .recordingExpand))
                .popover(isPresented: $showingTranscript, arrowEdge: .trailing) {
                    TranscriptFeed(model: model) { link in
                        showingTranscript = false
                        open(link)
                    }
                    .frame(width: Theme.Size.claudePanel, height: 320)
                }
            }
            .buttonStyle(.ghost)
            .tint(Theme.Palette.chromeIcon)
        }
        .padding(Theme.Space.m)
        .background {
            RecordingFace(
                shape: RoundedRectangle(cornerRadius: Theme.Radius.floating), accent: model.paused ? CourseAccent.gray : model.accent,
                recording: model.recording, level: recorder.level)
        }
        .animation(.smooth, value: model.paused)
        .environment(\.onGlass, true)
    }
}

private struct TranscriptFeed: View {
    let model: RecordingBarModel
    let open: (AppLink) -> Void
    @State private var showingContext = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            context
            Theme.Palette.lineSoft.frame(height: 1)
            feed
        }
        .onAppear { model.retellCaptionsIfChanged() }
    }

    @ViewBuilder var context: some View {
        Button {
            withAnimation(Theme.Motion.standard) { showingContext.toggle() }
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "doc.text").foregroundStyle(Theme.Palette.textTertiary)
                Text(model.contextSummary).lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: showingContext ? "chevron.up" : "chevron.down").font(Theme.Typeface.caption).foregroundStyle(
                    Theme.Palette.textTertiary)
            }
            .font(Theme.Typeface.caption)
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .help(Text(.recordingContextTitle))
        if showingContext, let context = model.context {
            ScrollView {
                Card {
                    TranscriptionContextRows(context: context, link: model.materialsLink.map { link in { open(link) } })
                }
                .padding([.horizontal, .bottom], Theme.Space.m)
            }
            .overflowFade(.vertical)
            .frame(maxHeight: 200)
            .transition(.opacity)
        }
    }

    var feed: some View {
        let recorder = model.recorder
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(Array(model.recentLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            Text(RecordingTime.label(line.start)).font(Theme.Typeface.label).monospacedDigit()
                                .foregroundStyle(Theme.Palette.textTertiary).frame(width: 44, alignment: .leading)
                            Text(line.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                    }
                    if !recorder.volatile.isEmpty {
                        Text(recorder.volatile).foregroundStyle(Theme.Palette.textTertiary).padding(.leading, 52)
                    }
                    if model.recentLines.isEmpty && recorder.volatile.isEmpty {
                        Text(model.line).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(Theme.Space.l)
            }
            .overflowFade(.vertical)
            .font(Theme.Typeface.body)
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: recorder.lines.count) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: recorder.volatile) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.xxs) {
            ForEach(0..<5, id: \.self) { i in
                let lit = Float(i) / 5 < level
                Capsule()
                    .fill(lit ? Theme.Palette.success : Theme.Palette.textTertiary.opacity(0.3))
                    .frame(width: 2, height: 4 + CGFloat([0, 2, 4, 2, 0][i]) + (lit ? CGFloat(level) * 4 : 0))
            }
        }
        .frame(height: Theme.Space.l)
        .animation(.easeOut(duration: 0.15), value: level)
        .accessibilityHidden(true)
    }
}
