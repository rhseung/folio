import SwiftUI

/// The recording under way, at the foot of the sidebar: the sidebar is on every page, and a bar floating over the
/// content hid what was under it for the whole class.
struct RecordingBar: View {
    @State private var model: RecordingBarModel
    @State private var showingTranscript = false
    let open: (Destination, SearchTarget?) -> Void

    init(workspace: Workspace, open: @escaping (Destination, SearchTarget?) -> Void) {
        _model = State(initialValue: RecordingBarModel(workspace: workspace))
        self.open = open
    }

    var body: some View {
        let recorder = model.recorder
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Button { if let id = model.course?.id { open(.course(id), nil) } } label: {
                        Text(model.courseTitle).font(Theme.Typeface.bodyStrong).foregroundStyle(model.accent.ink).lineLimit(1)
                    }
                    .help(Text(.recordingOpenCourse))
                    if let session = model.sessionName, let target = model.sessionTarget {
                        Button { open(.course(target.courseId), target) } label: {
                            Text(session).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                        }
                        .help(Text(target.noteId == nil ? .recordingOpenSessions : .recordingOpenSession))
                    }
                }
                .buttonStyle(.pointing(.plain))
                Spacer(minLength: Theme.Space.xs)
                Text(RecordingTime.label(recorder.elapsed))
                    .font(Theme.Typeface.figureSmall)
                    // Red while it records, gray while paused: the card's color is the course's, so the state needs its own.
                    .foregroundStyle(model.recording ? Theme.Palette.danger : Theme.Palette.textSecondary)
                    .contentTransition(.numericText())
            }
            // Two lines kept whether one or two are heard: a card changing height with every sentence moved the
            // sidebar's terms up and down under the pointer.
            Text(model.line)
                .font(Theme.Typeface.caption)
                .foregroundStyle(recorder.volatile.isEmpty ? Theme.Palette.text : Theme.Palette.textSecondary)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
            HStack(spacing: Theme.Space.m) {
                LevelMeter(level: model.recording ? recorder.level : 0)
                Spacer(minLength: 0)
                // Filled with a count once marked: an outline that only bounced looked as if the click did nothing.
                Button { recorder.bookmark() } label: {
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
                Button { model.toggle() } label: {
                    Image(systemName: model.recording ? "pause.fill" : "record.circle").contentTransition(.symbolEffect(.replace))
                }
                .help(Text(model.recording ? .recordingPause : .recordingResume))
                .disabled(model.preparing)
                Button { Task { await model.stop() } } label: { Image(systemName: "stop.fill") }
                .help(Text(.recordingStop))
                .disabled(model.preparing)
                Button { showingTranscript.toggle() } label: { Image(systemName: "text.quote") }
                    .help(Text(showingTranscript ? .recordingCollapse : .recordingExpand))
                    // Beside the sidebar, not inside it: the transcript wants a reading width the sidebar doesn't have.
                    .popover(isPresented: $showingTranscript, arrowEdge: .trailing) {
                        TranscriptFeed(model: model).frame(width: Theme.Size.claudePanel, height: 320)
                    }
            }
            .buttonStyle(.ghost)
            // One color for every button, the sidebar's own: blue buttons beside a red stop read as two kinds of control,
            // and the accent stood out among the sidebar's gray icons. The red time already says it is recording.
            .tint(Theme.Palette.chromeIcon)
        }
        .padding(Theme.Space.m)
        .background { RecordingCardFace(accent: model.accent, recording: model.recording) }
        .environment(\.onGlass, true)
    }
}

/// The course's tint and edge, like the 지금 수업 card on 오늘: the course's color without another icon or dot in a
/// sidebar already full of them. A tint, not a fill, since the sidebar is glass. While it records, a brighter tint and
/// edge breathe over it, so the card reads as live; paused, it holds still.
private struct RecordingCardFace: View {
    let accent: CourseAccent
    let recording: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.floating)
        ZStack {
            shape.fill(accent.tint)
            shape.strokeBorder(accent.color.opacity(Theme.Opacity.innerFill))
            ZStack {
                shape.fill(accent.color.opacity(Theme.Opacity.tint))
                shape.strokeBorder(accent.color.opacity(Theme.Opacity.ended))
            }
            .phaseAnimator([0.0, 1.0]) { glow, phase in
                glow.opacity(recording && !reduceMotion ? phase : 0)
            } animation: { _ in .easeInOut(duration: 1.4) }
        }
    }
}

private struct TranscriptFeed: View {
    let model: RecordingBarModel

    var body: some View {
        let recorder = model.recorder
        ScrollViewReader { proxy in
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
        // No taller than the buttons' glyphs beside it, at its loudest: a taller meter read as the row's one big control.
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

enum RecordingTime {
    static func label(_ seconds: TimeInterval) -> String {
        let s = Int(max(seconds, 0))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
