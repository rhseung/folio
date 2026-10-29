import SwiftUI

struct RecordingBar: View {
    @State private var model: RecordingBarModel
    @State private var expanded = false

    init(workspace: Workspace) {
        _model = State(initialValue: RecordingBarModel(workspace: workspace))
    }

    var body: some View {
        let recorder = model.recorder
        let recording = model.recording
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            ForEach(Array(model.recentLines.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                                    Text(RecordingTime.label(line.start)).font(Theme.Typeface.label).monospacedDigit()
                                        .foregroundStyle(Theme.Palette.textTertiary).frame(width: 44, alignment: .leading)
                                    Text(line.text).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            if !recorder.volatile.isEmpty {
                                Text(recorder.volatile).foregroundStyle(Theme.Palette.textTertiary).padding(.leading, 52)
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                    }
                    .frame(height: 220)
                    .onChange(of: recorder.lines.count) { proxy.scrollTo("end", anchor: .bottom) }
                    .onChange(of: recorder.volatile) { proxy.scrollTo("end", anchor: .bottom) }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: Theme.Space.m) {
                Circle()
                    .fill(recording ? Theme.Palette.danger : Theme.Palette.textTertiary)
                    .frame(width: 10, height: 10)
                    .phaseAnimator([1.0, 0.35]) { dot, phase in dot.opacity(recording ? phase : 1) } animation: { _ in .easeInOut(duration: 0.8) }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(model.title)
                        .font(Theme.Typeface.label).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                    Text(model.line)
                        .lineLimit(1).truncationMode(.head)
                        .foregroundStyle(recorder.volatile.isEmpty ? Theme.Palette.text : Theme.Palette.textSecondary)
                        .contentTransition(.opacity)
                }
                .frame(width: 300, alignment: .leading)
                LevelMeter(level: recorder.level)
                Text(RecordingTime.label(recorder.elapsed)).font(Theme.Typeface.bodyStrong).monospacedDigit().frame(width: 64)
                Button { recorder.bookmark() } label: { Image(systemName: "bookmark") }
                    .help(Text(.recordingBookmarkHelp(recorder.bookmarks.count)))
                    .symbolEffect(.bounce, value: recorder.bookmarks.count)
                Button { model.toggle() } label: {
                    Image(systemName: recording ? "pause.fill" : "record.circle").contentTransition(.symbolEffect(.replace))
                }
                .help(Text(recording ? .recordingPause : .recordingResume))
                .disabled(model.preparing)
                Button { Task { await model.stop() } } label: {
                    Image(systemName: "stop.fill").foregroundStyle(Theme.Palette.danger)
                }
                .help(Text(.recordingStop))
                .disabled(model.preparing)
                Button { withAnimation(.snappy(duration: 0.3)) { expanded.toggle() } } label: {
                    Image(systemName: "chevron.up").rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .help(Text(expanded ? .recordingCollapse : .recordingExpand))
            }
            .buttonStyle(.ghost)
        }
        .font(Theme.Typeface.body)
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .frame(width: 620)
        .floatingGlass()
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
                    .frame(width: 4, height: 6 + CGFloat([0, 4, 8, 4, 0][i]) + (lit ? CGFloat(level) * 6 : 0))
            }
        }
        .frame(height: 22)
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
