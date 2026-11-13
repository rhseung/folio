import AVFoundation
import SwiftUI

/// A smaller image stays at its own size rather than blown up to the pane.
struct ImagePane: View {
    let url: URL
    @State private var image: Image?
    @State private var size: CGSize = .zero
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFit()
                    .frame(maxWidth: size.width, maxHeight: size.height)
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                ContentUnavailableView(String(localized: .fileViewCannotRead), systemImage: "photo", description: Text(url.lastPathComponent))
            } else {
                ProgressView()
            }
        }
        .task(id: url) { await load() }
    }

    /// Decoded off the main thread: a phone photo is tens of megapixels.
    func load() async {
        let url = url
        let decoded = await Task.detached { () -> (PlatformImage, CGSize)? in
            guard let data = try? Data(contentsOf: url), let image = PlatformImage(data: data) else { return nil }
            return (image, image.size)
        }.value
        guard let (platform, pixels) = decoded else {
            failed = true
            return
        }
        #if os(macOS)
        image = Image(nsImage: platform)
        #else
        image = Image(uiImage: platform)
        #endif
        size = pixels
    }
}

/// An audio file under its name, played by the recording player's `AudioPlayback`. AVKit's `VideoPlayer` is not
/// used: in the Mac app its view class failed to load and took the app down.
struct AudioPane: View {
    let url: URL
    let name: String
    @State private var player = AudioPlayback()
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: "waveform").font(Theme.Glyph.large).foregroundStyle(Theme.Palette.textTertiary)
            Text(name).font(Theme.Typeface.bodyStrong).lineLimit(2).multilineTextAlignment(.center)
            HStack(spacing: Theme.Space.m) {
                Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }.help(Text(.recordingBack15))
                Button { player.toggle() } label: {
                    Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(Theme.Glyph.large).foregroundStyle(accent.color)
                        .contentTransition(.symbolEffect(.replace))
                }
                .keyboardShortcut(.space, modifiers: [])
                .help(Text(player.playing ? .recordingPause : .recordingPlay))
                Button { player.skip(15) } label: { Image(systemName: "goforward.15") }.help(Text(.recordingForward15))
                Text("\(RecordingTime.label(player.time)) / \(RecordingTime.label(player.duration))")
                    .monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
            }
            .buttonStyle(.ghost)
            track.frame(maxWidth: 480).frame(height: 20)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) { player.load(url) }
        .onDisappear { player.stop() }
    }

    var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let length = max(player.duration, 1)
            let x = w * CGFloat(min(player.time / length, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.fill).frame(height: 6)
                Capsule().fill(accent.color).frame(width: max(6, x), height: 6)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                player.seek(Double(min(max(g.location.x / w, 0), 1)) * length)
            })
            .pointingHand()
        }
    }
}
