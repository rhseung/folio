import AVFoundation
import FolioDomain
import FolioStorage
import SwiftUI

/// A class's recording to listen to, with its transcript, as a page of the course's sessions: an hour of listening
/// beside the slides and notes is no sheet's work (#317). Its address follows playback (`#t=12:30`), so the window
/// keeps the place through back and forward, a tab let go of opens where it was, and the link can be copied.
struct RecordingPage: View {
    @Environment(\.accent) private var accent
    @State private var model: RecordingPlayerModel
    @State private var deleting = false
    @State private var showingContext = false
    @FocusState private var linesFocused: Bool
    @FocusState private var pageFocused: Bool
    @Environment(\.openLink) private var openLink
    @Environment(\.tabPlaying) private var tabPlaying
    let place: AppLink
    let moved: (AppLink?) -> Void
    private var player: AudioPlayback { model.player }
    private var recording: Recording { model.recording }

    init(workspace: Workspace, course: LoadedCourse, recording: Recording, place: AppLink, moved: @escaping (AppLink?) -> Void) {
        _model = State(
            initialValue: RecordingPlayerModel(workspace: workspace, courseId: course.id, store: course.store, recording: recording))
        self.place = place
        self.moved = moved
    }

    var body: some View {
        let current = model.current
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(model.title).font(Theme.Typeface.pageTitle).lineLimit(2)
                    Text(model.subtitle).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.hasLines {
                    TextField(String(localized: .recordingSearch), text: $model.query).pill(width: 180)
                }
                PageMenuButton {
                    ItemMenu(source: RecordingMenuSource(model: model, host: .own, remove: { deleting = true }, openLink: openLink))
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
                        // Picking a line focuses the list so ⌘A and ⌘C reach it.
                        .focusable(interactions: .edit)
                        .focusEffectDisabled()
                        .focused($linesFocused)
                        .onLineCommand("a") { model.selectAll() }
                        .onLineCommand("c", model.canCopy ? { writePasteboard(model.copiedText) } : nil)
                        .onChange(of: current) { _, i in
                            guard let i, model.query.isEmpty, player.playing else { return }
                            withAnimation(Theme.Motion.settle) { proxy.scrollTo(i, anchor: .center) }
                        }
                        // Opened at a moment, the transcript starts at the line being said then.
                        .task(id: model.seekedTo) {
                            guard let line = model.seekedTo.flatMap(model.lineIndex) else { return }
                            try? await Task.sleep(for: .milliseconds(100))
                            proxy.scrollTo(line, anchor: .center)
                        }
                    }
                } else if model.phase == nil {
                    CardRow(last: true) {
                        EmptyLine(String(localized: .recordingEmpty))
                        if recording.hasAudio {
                            Button(.recordingTranscribe, systemImage: "waveform.badge.magnifyingglass") { model.transcribe() }
                                .buttonStyle(.prominent).disabled(!model.canTranscribe)
                        }
                    }
                }
            }
            // The transcript takes the page's height; without lines the card is a row and the rest stays up top.
            .frame(maxHeight: model.hasLines ? .infinity : nil, alignment: .top)
            if model.ranging {
                PickingLine(text: String(localized: .recordingPickingRange)) { model.endRange() }
            }
            if model.showsContext { contextBlock }
            // Words where they fit, the symbols alone in a narrow pane.
            ViewThatFits(in: .horizontal) {
                actions
                actions.labelStyle(.iconOnly)
            }
            if !model.hasLines { Spacer(minLength: 0) }
        }
        .frame(maxWidth: Theme.Size.pageMaxWidth, alignment: .leading)
        .padding(.horizontal, Theme.Space.xxl)
        .padding(.top, Theme.Space.xl)
        .clearOfColumnButtons(inset: Theme.Space.xl)
        // As `Page` leaves it, so the Claude button over the corner doesn't sit on the delete button.
        .padding(.bottom, Theme.Space.xxl * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Holds the focus the space bar needs, which a sheet had from its window and a page has to take.
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($pageFocused)
        .defaultFocus($pageFocused, true)
        .font(Theme.Typeface.body)
        .crumb(model.name, level: 2, symbol: "waveform")
        // On the page, not the button: the actions are drawn twice for `ViewThatFits`.
        .confirmationDialog(String(localized: .recordingRemoveConfirm), isPresented: $deleting) {
            Button(.recordingRemoveAction, role: .destructive) {
                model.remove()
                moved(nil)
            }
        } message: {
            Text(.recordingRemoveMessage)
        }
        .task { await model.loadContext() }
        // The window's link seeks the player; the player's moments go back as the window's link, in place of the step
        // it is on (`Navigator.go`), so listening adds no history.
        .onChange(of: place, initial: true) { _, link in model.follow(link) }
        .onChange(of: model.viewedLink) { _, link in moved(link) }
        .onChange(of: player.playing, initial: true) { _, playing in tabPlaying(playing ? { [player] in player.pause() } : nil) }
        .onDisappear {
            player.stop(); tabPlaying(nil)
        }
        // A finished job (or a cancelled one, which leaves the old transcript) has written what there is to show.
        .onChange(of: model.phase == nil) { _, done in if done { model.reloadTranscript() } }
    }

    /// A click on a control keeps the space bar on the player; a button takes no focus of its own on the Mac.
    func hold() {
        if !linesFocused { pageFocused = true }
    }

    var actions: some View {
        HStack {
            Button(model.copyLabel, systemImage: "doc.on.doc") { writePasteboard(model.copiedText) }.disabled(!model.canCopy)
                .help(Text(.recordingCopyHelp))
            if model.hasLines {
                // ⌘A's button, for a screen with no keyboard.
                Button(.recordingSelectAll, systemImage: "checklist") { model.selectAll() }.disabled(model.allSelected)
            }
            if model.hasLines && recording.hasAudio {
                Button(.recordingRetranscribe, systemImage: "arrow.clockwise") { model.transcribe() }
                    .disabled(!model.canTranscribe)
                    .help(Text(.recordingRetranscribeHelp))
            }
            Spacer()
            Button(.recordingRemove, systemImage: "trash", role: .destructive) { deleting = true }
                .disabled(model.removalRefusal != nil)
                .help(model.removalRefusal.map { Text($0) } ?? Text(.recordingRemove))
        }
        .buttonStyle(.ghost)
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
                Button {
                    withAnimation(Theme.Motion.standard) { showingContext.toggle() }
                } label: {
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
                            openLink(model.materialsLink, course: model.courseId)
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
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(model.bookmarks, id: \.self) { mark in
                        Button(RecordingTime.label(mark)) {
                            model.jump(to: mark); hold()
                        }
                        .monospacedDigit().buttonStyle(.ghost)
                        .help(Text(.recordingBookmarkJump))
                    }
                }
            }
            .overflowFade(.horizontal)
        }
        .font(Theme.Typeface.caption)
    }

    var transport: some View {
        HStack(spacing: Theme.Space.m) {
            Button {
                player.skip(-15)
            } label: {
                Image(systemName: "gobackward.15")
            }.help(Text(.recordingBack15))
            Button {
                player.toggle(); hold()
            } label: {
                Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(accent.color)  // design: one-off, play is the player's one large control
                    .contentTransition(.symbolEffect(.replace))
            }
            // Only while the page has the focus: a window-wide space bar would take the spaces typed in the search
            // field or the Claude panel over it.
            .keyboardShortcut(pageFocused || linesFocused ? KeyboardShortcut(.space, modifiers: []) : nil)
            .help(Text(player.playing ? .recordingPause : .recordingPlay))
            Button {
                player.skip(15)
            } label: {
                Image(systemName: "goforward.15")
            }.help(Text(.recordingForward15))
            Text(RecordingTime.label(player.time)).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary).frame(
                width: 56, alignment: .trailing)
            track.frame(height: 20)
            Menu(String(format: "%gx", player.rate)) {
                ForEach([1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in Button(String(format: "%gx", rate)) { player.rate = Float(rate) }
                }
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
                Circle().fill(.white)  // design: one-off, a slider knob stays white in both appearances, as in the system
                    .frame(width: 14, height: 14)  // design: one-off, the system slider knob's size
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)  // design: one-off, and its shadow
                    .offset(x: min(max(x - 7, 0), w - 14))
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    player.seek(Double(min(max(g.location.x / w, 0), 1)) * length)
                }
            )
            .pointingHand()
        }
    }

    /// Clicking the line picks it for copying and the time jumps there. A click that also jumped would move playback
    /// with every pick and Shift-click, losing the place being listened to while choosing what to copy.
    func row(_ index: Int, _ line: LectureTranscript.Line, playing: Bool, selected: Bool, bookmarked: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Button {
                model.jump(to: line.start); hold()
            } label: {
                Text(RecordingTime.label(line.start)).font(Theme.Typeface.label).monospacedDigit()
                    .foregroundStyle(playing ? accent.ink : Theme.Palette.textTertiary).frame(width: 52, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .help(Text(.recordingLinePlay))
            // With the audio gone there is nothing to seek to; the line can still be picked and copied.
            .allowsHitTesting(recording.hasAudio)
            // The pick covers the row but the time, whose press jumps instead.
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Text(line.text).foregroundStyle(playing || selected ? Theme.Palette.text : Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let visit = model.page(at: index) {
                    // Beside the replay, which keeps playing: the slides are what the class was saying it over.
                    Button(model.pageLabel(visit)) {
                        openLink(model.pageLink(visit), in: .beside, course: model.courseId)
                    }
                    .font(Theme.Typeface.label).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
                    .buttonStyle(.pointing(.plain))
                    .help(Text(model.pageHelp(visit)))
                }
                if bookmarked { Image(systemName: "bookmark.fill").font(Theme.Typeface.label).foregroundStyle(Theme.Palette.warning) }
            }
            .padding(.vertical, Theme.Inset.listRow.top)
            .padding(.trailing, Theme.Inset.listRow.trailing)
            .picks(picking: model.ranging, touch: .range) {
                model.hold(index)
                linesFocused = true
            } _: { press in
                model.select(index, extending: press == .range)
                linesFocused = true
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(.leading, Theme.Inset.listRow.leading)
        // The pick wins over the playing tint: otherwise picking the playing line would show no change. The playing
        // line still keeps its accent time.
        .background(selected ? Theme.Palette.fill : playing ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
        .animation(Theme.Motion.standard, value: playing)
    }
}

private extension View {
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

@MainActor func writePasteboard(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #else
    UIPasteboard.general.string = text
    #endif
}

@MainActor @Observable
final class AudioPlayback {
    private(set) var time: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var playing = false
    var rate: Float = 1 { didSet { player?.rate = rate } }
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var clock: Task<Void, Never>?

    /// `expected`: the length the recording kept, shown while the audio can't be read (still downloading from iCloud).
    func load(_ url: URL, expected: TimeInterval = 0) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        player?.prepareToPlay()
        duration = player?.duration ?? expected
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
