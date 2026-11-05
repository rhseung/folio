import AVFoundation
import FolioDomain
import FolioStorage
import SwiftUI

struct RecordingPlayer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    let title: String
    @State private var model: RecordingPlayerModel
    @State private var deleting = false
    @State private var showingContext = false
    @FocusState private var linesFocused: Bool
    @Environment(\.searchTarget) private var searchTarget
    private var player: AudioPlayback { model.player }
    private var recording: Recording { model.recording }

    init(workspace: Workspace, courseId: UUID, store: CourseStore, recording: Recording, title: String) {
        _model = State(initialValue: RecordingPlayerModel(workspace: workspace, courseId: courseId, store: store, recording: recording))
        self.title = title
    }

    var body: some View {
        let current = model.current
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title).font(Theme.Typeface.columnTitle)
                    Text(model.subtitle)
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                if model.hasLines {
                    TextField(String(localized: .recordingSearch), text: $model.query).pill(width: 180)
                }
            }
            if recording.hasAudio {
                transport
                if !model.bookmarks.isEmpty { bookmarkStrip }
            } else {
                Label(.recordingAudioTrashed, systemImage: "waveform.slash")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
            }
            Card {
                if model.phase != nil { progressRow }
                if model.hasLines {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                ForEach(model.shownLines, id: \.index) { i, line, bookmarked in
                                    row(i, line, playing: i == current, selected: model.selected.contains(i), bookmarked: bookmarked)
                                        .id(i)
                                }
                            }
                            .padding(Theme.Space.s)
                        }
                        // Picking a line focuses the list so ⌘A and ⌘C reach it. The sheet still opens on the search
                        // field: `defaultFocus`, `prefersDefaultFocus` and setting focus in `.task` all lost to it.
                        .focusable(interactions: .edit)
                        .focusEffectDisabled()
                        .focused($linesFocused)
                        .onLineCommand("a") { model.selectAll() }
                        .onLineCommand("c", model.canCopy ? { writePasteboard(model.copiedText) } : nil)
                        .onChange(of: current) { _, i in
                            guard let i, model.query.isEmpty, player.playing else { return }
                            withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(i, anchor: .center) }
                        }
                    }
                } else if model.phase == nil {
                    CardRow(last: true) {
                        EmptyLine(String(localized: .recordingEmpty))
                        if recording.hasAudio {
                            Button(.recordingTranscribe, systemImage: "waveform.badge.magnifyingglass") { model.transcribe() }
                                .buttonStyle(.pointing(.borderedProminent)).disabled(!model.canTranscribe)
                        }
                    }
                }
            }
            if model.showsContext { contextBlock }
            HStack {
                Button(model.copyLabel, systemImage: "doc.on.doc") { writePasteboard(model.copiedText) }.disabled(!model.canCopy)
                    .buttonStyle(.ghost)
                    .help(Text(.recordingCopyHelp))
                if model.hasLines && recording.hasAudio {
                    Button(.recordingRetranscribe, systemImage: "arrow.clockwise") { model.transcribe() }
                        .buttonStyle(.ghost).disabled(!model.canTranscribe)
                        .help(Text(.recordingRetranscribeHelp))
                }
                Button(.recordingRemove, systemImage: "trash", role: .destructive) { deleting = true }
                    .buttonStyle(.ghost)
                    .disabled(model.removalRefusal != nil)
                    .help(model.removalRefusal.map { Text($0) } ?? Text(.recordingRemove))
                    .confirmationDialog(String(localized: .recordingRemoveConfirm), isPresented: $deleting) {
                        Button(.recordingRemoveAction, role: .destructive) {
                            model.remove()
                            dismiss()
                        }
                    } message: {
                        Text(.recordingRemoveMessage)
                    }
                Spacer()
                Button(.commonClose) { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.pointing(.borderedProminent))
            }
        }
        .padding(Theme.Space.xl)
        // Tall only with lines to scroll: a recording without a transcript sat in the middle of an empty sheet.
        .frame(width: 640, height: model.hasLines ? 680 : nil)
        .background(Theme.Palette.page)
        .font(Theme.Typeface.body)
        .task {
            model.load()
            await model.loadContext()
        }
        .onDisappear { player.stop() }
        // A finished job (or a cancelled one, which leaves the old transcript) has written what there is to show.
        .onChange(of: model.phase == nil) { _, done in if done { model.reloadTranscript() } }
    }

    /// Folded to one line under the transcript: it explains the transcript, it isn't what the player is for.
    var contextBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if model.contextChanged {
                NoticeCard(title: String(localized: .recordingContextChanged), detail: String(localized: .recordingContextChangedDetail)) {
                    Button(.recordingRetranscribe) { model.transcribe() }.buttonStyle(.ghost).disabled(!model.canTranscribe)
                }
            }
            Block(title: String(localized: .recordingContextTitle), note: model.contextSummary) {
                Button { withAnimation(.snappy(duration: 0.25)) { showingContext.toggle() } } label: {
                    Image(systemName: showingContext ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.ghost)
                .help(Text(showingContext ? .recordingContextHide : .recordingContextShow))
            } content: {
                if showingContext, let context = model.shownContext {
                    if let note = model.contextNote {
                        Text(note).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Card {
                        TranscriptionContextRows(context: context, termsRead: model.contextTermsRead) {
                            searchTarget.wrappedValue = model.materialsTarget
                            dismiss()
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    var progressRow: some View {
        CardRow(last: !model.hasLines) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(model.phaseLabel).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                if let fraction = model.phaseFraction {
                    ProgressView(value: fraction).progressViewStyle(.linear).tint(accent.color)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(accent.color)
                }
                Text(.recordingTranscribeClosable).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
            Button(.commonCancel) { model.cancelTranscription() }.buttonStyle(.ghost)
        }
    }

    /// Marks made while recording, as places to jump to: without a transcript the track's ticks were the only sign of them.
    var bookmarkStrip: some View {
        HStack(spacing: Theme.Space.s) {
            Label(.recordingBookmarks, systemImage: "bookmark.fill").labelStyle(.iconOnly).foregroundStyle(Theme.Palette.warning)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(model.bookmarks, id: \.self) { mark in
                        Button(RecordingTime.label(mark)) { player.seek(mark); player.play() }
                            .monospacedDigit().buttonStyle(.ghost)
                            .help(Text(.recordingBookmarkJump))
                    }
                }
            }
        }
        .font(Theme.Typeface.caption)
    }

    var transport: some View {
        HStack(spacing: Theme.Space.m) {
            Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }.help(Text(.recordingBack15))
            Button { player.toggle() } label: {
                Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(accent.color) // design: one-off, play is the player's one large control
                    .contentTransition(.symbolEffect(.replace))
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(Text(player.playing ? .recordingPause : .recordingPlay))
            Button { player.skip(15) } label: { Image(systemName: "goforward.15") }.help(Text(.recordingForward15))
            Text(RecordingTime.label(player.time)).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary).frame(width: 56, alignment: .trailing)
            track.frame(height: 20)
            Menu(String(format: "%gx", player.rate)) {
                ForEach([1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in Button(String(format: "%gx", rate)) { player.rate = Float(rate) } }
            }
            .menuStyle(.button).buttonStyle(.borderless).pointingHand().fixedSize()
            .help(Text(.recordingRate))
        }
        .buttonStyle(.ghost)
    }

    /// The marks live inside this fixed-height frame: in a stack beside the bar, their GeometryReader took all the height.
    var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let length = max(player.duration, 1)
            let x = w * CGFloat(min(player.time / length, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.fill).frame(height: 6)
                Capsule().fill(accent.color).frame(width: max(6, x), height: 6)
                ForEach(recording.bookmarks, id: \.self) { mark in
                    Capsule().fill(Theme.Palette.warning).frame(width: 4, height: 12)
                        .offset(x: w * CGFloat(mark / length) - 2)
                }
                Circle().fill(.white).frame(width: 14, height: 14).shadow(color: .black.opacity(0.25), radius: 2, y: 1) // design: one-off, a slider knob stays white in both appearances, as in the system
                    .offset(x: min(max(x - 7, 0), w - 14))
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                player.seek(Double(min(max(g.location.x / w, 0), 1)) * length)
            })
            .pointingHand()
        }
    }

    /// Clicking the line picks it for copying and the time jumps there. A click that also jumped would move playback
    /// with every pick and Shift-click, losing the place being listened to while choosing what to copy.
    func row(_ index: Int, _ line: LectureTranscript.Line, playing: Bool, selected: Bool, bookmarked: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Button { player.seek(line.start); player.play() } label: {
                Text(RecordingTime.label(line.start)).font(Theme.Typeface.label).monospacedDigit()
                    .foregroundStyle(playing ? accent.ink : Theme.Palette.textTertiary).frame(width: 52, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .help(Text(.recordingLinePlay))
            // With the audio gone there is nothing to seek to; the line can still be picked and copied.
            .allowsHitTesting(recording.hasAudio)
            // The pick covers the row but the time: over the time too, iPad's UIKit tap would fire beside the
            // button's jump and pick the line, while the Mac's button keeps the click to itself.
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Text(line.text).foregroundStyle(playing || selected ? Theme.Palette.text : Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if bookmarked { Image(systemName: "bookmark.fill").font(Theme.Typeface.label).foregroundStyle(Theme.Palette.warning) }
            }
            .padding(.vertical, Theme.Inset.listRow.top)
            .padding(.trailing, Theme.Inset.listRow.trailing)
            .contentShape(.rect)
            .onPick { extending in
                model.select(index, extending: extending)
                linesFocused = true
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(.leading, Theme.Inset.listRow.leading)
        // The pick wins over the playing tint: otherwise picking the playing line would show no change. The playing
        // line still keeps its accent time.
        .background(selected ? Theme.Palette.fill : playing ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
        .animation(.snappy(duration: 0.25), value: playing)
    }
}

private extension View {
    /// A tap that says whether Shift was held, to extend a pick. SwiftUI's tap carries no modifier keys.
    func onPick(_ action: @escaping (_ extending: Bool) -> Void) -> some View {
        #if os(macOS)
        // The click's own flags: the keyboard's live state (`NSEvent.modifierFlags`) misses a Shift the click carries
        // but no key holds, as from Accessibility or a scripted click.
        onTapGesture { action((NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).contains(.shift)) }
        #else
        // UIKit's recognizer reads the hardware keyboard's Shift; touch alone has no way to extend.
        gesture(PickTap(action: action))
        #endif
    }

    /// ⌘A (`"a"`) or ⌘C (`"c"`) on the focused lines; `nil` leaves the command off. A button shortcut on the Mac
    /// would take the key from the search field even while it is being typed in, so there it goes through the
    /// responder chain as the Edit menu's command.
    func onLineCommand(_ key: KeyEquivalent, _ action: (() -> Void)?) -> some View {
        #if os(macOS)
        onCommand(key == "a" ? #selector(NSText.selectAll(_:)) : #selector(NSText.copy(_:)), perform: action)
        #else
        onKeyPress(keys: [key]) { press in
            guard press.modifiers.contains(.command), let action else { return .ignored }
            action()
            return .handled
        }
        #endif
    }
}

@MainActor private func writePasteboard(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #else
    UIPasteboard.general.string = text
    #endif
}

#if os(iOS)
private struct PickTap: UIGestureRecognizerRepresentable {
    let action: (_ extending: Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer { UITapGestureRecognizer() }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        guard recognizer.state == .ended else { return }
        action(recognizer.modifierFlags.contains(.shift))
    }
}
#endif

@MainActor @Observable
final class AudioPlayback {
    private(set) var time: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var playing = false
    var rate: Float = 1 { didSet { player?.rate = rate } }
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var clock: Task<Void, Never>?

    func load(_ url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    func play() {
        guard let player else { return }
        player.rate = rate
        player.play()
        playing = true
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, let player = self.player else { return }
                self.time = player.currentTime
                if !player.isPlaying { self.playing = false; return }
            }
        }
    }

    func pause() {
        player?.pause()
        playing = false
        clock?.cancel()
    }

    func toggle() { playing ? pause() : play() }

    func seek(_ seconds: TimeInterval) {
        let t = min(max(seconds, 0), duration)
        player?.currentTime = t
        time = t
    }

    func skip(_ seconds: TimeInterval) { seek(time + seconds) }

    func stop() {
        pause()
        player?.stop()
    }
}
