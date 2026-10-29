import AVFoundation
import FolioDomain
import FolioStorage
import SwiftUI

struct RecordingPlayer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    let courseId: UUID
    let store: CourseStore
    let recording: Recording
    let title: String
    @State private var player = AudioPlayback()
    @State private var transcript: LectureTranscript?
    @State private var query = ""
    @State private var deleting = false

    var body: some View {
        let current = transcript?.lineIndex(at: player.time)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title).font(Theme.Typeface.columnTitle)
                    Text(recording.startedAt.formatted(date: .abbreviated, time: .shortened) + " · " + RecordingTime.label(player.duration))
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                Spacer()
                TextField("받아쓰기에서 찾기", text: $query).pill(width: 180)
            }
            transport
            Card {
                if let transcript, !transcript.lines.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                ForEach(Array(transcript.lines.enumerated()), id: \.offset) { i, line in
                                    if query.isEmpty || line.text.localizedCaseInsensitiveContains(query) {
                                        row(line, playing: i == current, bookmarked: recording.bookmarks.contains { line.start <= $0 && $0 < line.end + 1 })
                                            .id(i)
                                    }
                                }
                            }
                            .padding(Theme.Space.s)
                        }
                        .onChange(of: current) { _, i in
                            guard let i, query.isEmpty, player.playing else { return }
                            withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(i, anchor: .center) }
                        }
                    }
                } else {
                    CardRow(last: true) { EmptyLine("받아쓴 내용이 없습니다.") }
                }
            }
            HStack {
                Button("받아쓰기 복사", systemImage: "doc.on.doc") { copy(transcript?.text ?? "") }.disabled(transcript?.lines.isEmpty ?? true)
                    .buttonStyle(.ghost)
                Button("녹음 삭제", systemImage: "trash", role: .destructive) { deleting = true }
                    .buttonStyle(.ghost)
                    .confirmationDialog("이 녹음을 삭제할까요?", isPresented: $deleting) {
                        Button("녹음과 받아쓰기 삭제", role: .destructive) {
                            player.stop()
                            workspace.deleteRecording(recording, course: courseId)
                            dismiss()
                        }
                    } message: {
                        Text("오디오 파일과 받아쓴 내용을 지웁니다. 되돌릴 수 없습니다.")
                    }
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.pointing(.borderedProminent))
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 640, height: 680)
        .background(Theme.Palette.page)
        .font(Theme.Typeface.body)
        .task {
            transcript = store.transcript(of: recording)
            player.load(store.fileURL(recording.file))
        }
        .onDisappear { player.stop() }
    }

    var transport: some View {
        HStack(spacing: Theme.Space.m) {
            Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }.help("15초 뒤로")
            Button { player.toggle() } label: {
                Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34)).foregroundStyle(accent.color) // design: one-off, play is the player's one large control
                    .contentTransition(.symbolEffect(.replace))
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(player.playing ? "일시 정지" : "재생")
            Button { player.skip(15) } label: { Image(systemName: "goforward.15") }.help("15초 앞으로")
            Text(RecordingTime.label(player.time)).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary).frame(width: 56, alignment: .trailing)
            track.frame(height: 20)
            Menu(String(format: "%gx", player.rate)) {
                ForEach([1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in Button(String(format: "%gx", rate)) { player.rate = Float(rate) } }
            }
            .menuStyle(.button).buttonStyle(.borderless).pointingHand().fixedSize()
            .help("재생 속도")
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

    func row(_ line: LectureTranscript.Line, playing: Bool, bookmarked: Bool) -> some View {
        Button { player.seek(line.start); player.play() } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Text(RecordingTime.label(line.start)).font(Theme.Typeface.label).monospacedDigit()
                    .foregroundStyle(playing ? accent.ink : Theme.Palette.textTertiary).frame(width: 52, alignment: .leading)
                Text(line.text).foregroundStyle(playing ? Theme.Palette.text : Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if bookmarked { Image(systemName: "bookmark.fill").font(Theme.Typeface.label).foregroundStyle(Theme.Palette.warning) }
            }
            .padding(Theme.Inset.listRow)
            .background(playing ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .animation(.snappy(duration: 0.25), value: playing)
    }

    func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

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
