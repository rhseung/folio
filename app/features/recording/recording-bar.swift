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
                        Text(model.courseTitle).font(Theme.Typeface.bodyStrong).foregroundStyle(model.paused ? Theme.Palette.textSecondary : model.accent.ink).lineLimit(1)
                    }
                    .help(Text(.recordingOpenCourse))
                    if let session = model.sessionName, let target = model.sessionTarget {
                        Button { open(.course(target.courseId), target) } label: {
                            Text(session).font(Theme.Typeface.caption).foregroundStyle(model.paused ? Theme.Palette.textTertiary : Theme.Palette.textSecondary).lineLimit(1)
                        }
                        .help(Text(target.noteId == nil ? .recordingOpenSessions : .recordingOpenSession))
                    }
                }
                .buttonStyle(.pointing(.plain))
                Spacer(minLength: Theme.Space.xs)
                Text(RecordingTime.label(recorder.elapsed))
                    .font(Theme.Typeface.figureSmall)
                    // Red while it records, gray while paused: the card's color is the course's, so the state needs its own.
                    .foregroundStyle(model.paused ? Theme.Palette.textSecondary : Theme.Palette.danger)
                    .contentTransition(.numericText())
            }
            // Two lines kept whether one or two are heard: a card changing height with every sentence moved the
            // sidebar's terms up and down under the pointer.
            Text(model.line)
                .font(Theme.Typeface.caption)
                .foregroundStyle(model.paused ? Theme.Palette.textTertiary : recorder.volatile.isEmpty ? Theme.Palette.text : Theme.Palette.textSecondary)
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
                .disabled(model.settling)
                Button { model.toggle() } label: {
                    // Only a pause offers to resume; starting and stopping keep the pause glyph, switched off.
                    Image(systemName: model.paused ? "record.circle" : "pause.fill").contentTransition(.symbolEffect(.replace))
                }
                .help(Text(model.paused ? .recordingResume : .recordingPause))
                .disabled(model.settling)
                Button { Task { await model.stop() } } label: { Image(systemName: "stop.fill") }
                .help(Text(.recordingStop))
                .disabled(model.settling)
                Button { showingTranscript.toggle() } label: { Image(systemName: "text.quote") }
                    .help(Text(showingTranscript ? .recordingCollapse : .recordingExpand))
                    // Beside the sidebar, not inside it: the transcript wants a reading width the sidebar doesn't have.
                    .popover(isPresented: $showingTranscript, arrowEdge: .trailing) {
                        TranscriptFeed(model: model) { target in
                            showingTranscript = false
                            open(.course(target.courseId), target)
                        }
                        .frame(width: Theme.Size.claudePanel, height: 320)
                    }
            }
            .buttonStyle(.ghost)
            // One color for every button, the sidebar's own: blue buttons beside a red stop read as two kinds of control,
            // and the accent stood out among the sidebar's gray icons. The red time already says it is recording.
            .tint(Theme.Palette.chromeIcon)
        }
        .padding(Theme.Space.m)
        // Paused, the card goes gray and its words fade, like a control switched off; the buttons keep their color, since
        // resume and stop are what the card is for then.
        .background { RecordingCardFace(accent: model.paused ? CourseAccent.gray : model.accent, recording: model.recording, level: recorder.level) }
        .animation(.smooth, value: model.paused)
        .environment(\.onGlass, true)
    }
}

/// The course's tint and edge, like the 지금 수업 card on 오늘: the course's color without another icon or dot in a
/// sidebar already full of them. A tint, not a fill, since the sidebar is glass.
///
/// While it records, a glow swells from the level meter's corner as the lecturer speaks and settles in a pause: a
/// whole-card fade on a fixed beat read as blinking, not listening.
private struct RecordingCardFace: View {
    let accent: CourseAccent
    let recording: Bool
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.floating)
        let voice = recording ? CGFloat(level) : 0
        ZStack {
            shape.fill(accent.tint)
            shape.strokeBorder(accent.color.opacity(Theme.Opacity.innerFill))
            GeometryReader { proxy in
                let reach = max(proxy.size.width, proxy.size.height)
                // A circle around the corner, not a gradient filling the card: shrunk below the card's height, the card-
                // sized fill showed its top edge as a line across the glow.
                Circle()
                    .fill(RadialGradient(colors: [accent.color.opacity(Theme.Opacity.voiceGlow), accent.color.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: reach))
                    .frame(width: reach * 2, height: reach * 2)
                    .position(x: 0, y: proxy.size.height)
                    // Scaled from the corner, not the radius changed: SwiftUI eases a scale between level samples, where a
                    // new gradient radius jumps.
                    .scaleEffect(reduceMotion ? 1 : 0.5 + 1.1 * voice, anchor: .bottomLeading)
                    // Square root: the size already grows with the voice, and a linear fade on top of it left a
                    // speaking voice barely brighter than silence.
                    .opacity(Double(voice).squareRoot())
            }
            .clipShape(shape)
        }
        // Eased, not sprung: the level comes five times a second, and a spring overshot each sample into a flicker.
        .animation(.smooth(duration: 0.35), value: voice)
    }
}

private struct TranscriptFeed: View {
    let model: RecordingBarModel
    let open: (SearchTarget) -> Void
    @State private var showingContext = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            context
            Theme.Palette.lineSoft.frame(height: 1)
            feed
        }
        // Links made since the captions were told (from this popover's own link, say) reach them now.
        .onAppear { model.retellCaptionsIfChanged() }
    }

    /// One line above the captions, so the card itself stays as it is: what the captions were told, opened on a click.
    @ViewBuilder var context: some View {
        Button { withAnimation(.snappy(duration: 0.25)) { showingContext.toggle() } } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "doc.text").foregroundStyle(Theme.Palette.textTertiary)
                Text(model.contextSummary).lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: showingContext ? "chevron.up" : "chevron.down").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
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
                    TranscriptionContextRows(context: context, link: model.materialsTarget.map { target in { open(target) } })
                }
                .padding([.horizontal, .bottom], Theme.Space.m)
            }
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
