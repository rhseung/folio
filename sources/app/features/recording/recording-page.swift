import AVFoundation
import FolioDomain
import FolioStorage
import SwiftUI

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
                        .focusable(interactions: .edit)
                        .focusEffectDisabled()
                        .focused($linesFocused)
                        .onLineCommand("a") { model.selectAll() }
                        .onLineCommand("c", model.canCopy ? { writePasteboard(model.copiedText) } : nil)
                        .onChange(of: current) { _, i in
                            guard let i, model.query.isEmpty, player.playing else { return }
                            withAnimation(Theme.Motion.settle) { proxy.scrollTo(i, anchor: .center) }
                        }
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
            .frame(maxHeight: model.hasLines ? .infinity : nil, alignment: .top)
            if model.ranging {
                PickingLine(text: String(localized: .recordingPickingRange)) { model.endRange() }
            }
            if model.showsContext { contextBlock }
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
        .padding(.bottom, Theme.Space.xxl * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 스페이스 바에 필요한 초점을 잡는다. 시트는 창에서 초점을 받았지만 페이지는 직접 잡아야 한다.
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($pageFocused)
        .defaultFocus($pageFocused, true)
        .font(Theme.Typeface.body)
        .crumb(model.name, level: 2, symbol: "waveform")
        // `ViewThatFits` 때문에 동작이 두 번 그려지므로 버튼이 아니라 페이지에 단다.
        .confirmationDialog(String(localized: .recordingRemoveConfirm), isPresented: $deleting) {
            Button(.recordingRemoveAction, role: .destructive) {
                model.remove()
                moved(nil)
            }
        } message: {
            Text(.recordingRemoveMessage)
        }
        .task { await model.loadContext() }
        .onChange(of: place, initial: true) { _, link in model.follow(link) }
        .onChange(of: model.viewedLink) { _, link in moved(link) }
        .onChange(of: player.playing, initial: true) { _, playing in tabPlaying(playing ? { [player] in player.pause() } : nil) }
        .onDisappear {
            player.stop(); tabPlaying(nil)
        }
        .onChange(of: model.phase == nil) { _, done in if done { model.reloadTranscript() } }
    }

    // Mac에서 버튼은 초점을 받지 않으므로, 컨트롤을 클릭해도 스페이스 바가 플레이어에 남게 한다.
    func hold() {
        if !linesFocused { pageFocused = true }
    }

    var actions: some View {
        HStack {
            Button(model.copyLabel, systemImage: "doc.on.doc") { writePasteboard(model.copiedText) }.disabled(!model.canCopy)
                .help(Text(.recordingCopyHelp))
            if model.hasLines {
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
            // 페이지에 초점이 있을 때만 단다. 창 전체의 스페이스 바는 검색 칸이나 그 위의 Claude 패널에 친 공백을
            // 가져간다.
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

    // 표시를 이 고정 높이 frame 안에 둔다. 바 옆의 stack에 두면 GeometryReader가 높이를 모두 가져갔다.
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
            .allowsHitTesting(recording.hasAudio)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Text(line.text).foregroundStyle(playing || selected ? Theme.Palette.text : Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let visit = model.page(at: index) {
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
        .background(selected ? Theme.Palette.fill : playing ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
        .animation(Theme.Motion.standard, value: playing)
    }
}

private extension View {
    // Mac에서 버튼 단축키는 검색 칸에 입력하는 중에도 키를 가져가므로, Edit 메뉴의 명령처럼 responder chain으로 보낸다.
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
